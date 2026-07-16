import SwiftUI
import AVFoundation
import AVKit
import Combine
import UIKit

// MARK: - Orientation

enum LongFormOrientation {
    static func lock(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
    }
}

// MARK: - Player model

@MainActor
final class LongFormPlayerModel: ObservableObject {
    @Published var isPlaying = false
    @Published var isReady = false
    @Published var failed = false
    @Published var current: Double = 0
    @Published var duration: Double = 1
    @Published var controlsVisible = true
    @Published var isMuted = false
    @Published var isFullscreen = false
    /// Accumulated double-tap skip flash (seconds, signed: negative = rewind).
    @Published var skipFlashSeconds: Int = 0
    @Published var skipFlashForward: Bool = true

    let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var rateObserver: NSKeyValueObservation?
    private var hideTask: Task<Void, Never>?
    private var skipFlashTask: Task<Void, Never>?
    private var loadedURL: String?

    func load(urlString: String?, autoplay: Bool = true) {
        let raw = VideoLibrary.resolve(urlString) ?? SampleData.repairedVideoURL(urlString)
        guard let raw, !raw.isEmpty else {
            failed = urlString != nil
            return
        }
        if loadedURL == raw, player.currentItem != nil {
            if autoplay { play() }
            return
        }
        teardownItem()
        loadedURL = raw
        failed = false
        isReady = false
        current = 0
        duration = 1

        guard let url = Self.resolveURL(raw) else {
            failed = true
            return
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.isMuted = isMuted

        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isReady = true
                    self.failed = false
                    let d = item.duration.seconds
                    if d.isFinite, d > 0 { self.duration = d }
                    if autoplay { self.play() }
                case .failed:
                    self.isReady = false
                    self.failed = true
                default:
                    break
                }
            }
        }

        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] p, _ in
            Task { @MainActor in
                self?.isPlaying = p.rate > 0
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let s = time.seconds
            if s.isFinite { self.current = max(0, s) }
            if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                self.duration = d
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.player.seek(to: .zero)
                self?.isPlaying = false
                self?.showControls()
            }
        }
    }

    func play() {
        player.play()
        isPlaying = true
        scheduleHideControls()
    }

    func pause() {
        player.pause()
        isPlaying = false
        showControls()
    }

    func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to seconds: Double) {
        let t = max(0, min(seconds, duration))
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        current = t
    }

    func skip(by delta: Double) {
        seek(to: current + delta)
    }

    /// Double-tap skip: each tap adds ±10s and the flash total accumulates while taps keep coming.
    func accumulateSkip(forward: Bool) {
        let step = 10
        if skipFlashSeconds != 0, skipFlashForward != forward {
            skipFlashSeconds = 0
        }
        skipFlashForward = forward
        skipFlashSeconds += step
        skip(by: forward ? Double(step) : -Double(step))
        // Keep video playing through skips; don't toggle chrome on each tap.
        if !isPlaying { play() }

        skipFlashTask?.cancel()
        skipFlashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                skipFlashSeconds = 0
            }
        }
    }

    func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
    }

    func showControls() {
        controlsVisible = true
        scheduleHideControls()
    }

    func toggleControls() {
        if controlsVisible {
            hideTask?.cancel()
            controlsVisible = false
        } else {
            showControls()
        }
    }

    func enterFullscreen() {
        showControls()
        // Rotate first, then flip layout once geometry is ready — avoids a zero-height frame.
        LongFormOrientation.lock(.landscapeRight)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.isFullscreen = true
            self.player.play()
            self.isPlaying = true
            self.scheduleHideControls()
        }
    }

    func exitFullscreen() {
        isFullscreen = false
        LongFormOrientation.lock(.portrait)
        showControls()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.player.play()
            self.isPlaying = true
            self.scheduleHideControls()
        }
    }

    func shutdown() {
        hideTask?.cancel()
        skipFlashTask?.cancel()
        if isFullscreen { exitFullscreen() }
        teardownItem()
        player.pause()
        loadedURL = nil
        skipFlashSeconds = 0
    }

    private func scheduleHideControls() {
        hideTask?.cancel()
        guard isPlaying else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, isPlaying else { return }
            withAnimation(.easeOut(duration: 0.2)) { controlsVisible = false }
        }
    }

    private func teardownItem() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        rateObserver?.invalidate()
        rateObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.replaceCurrentItem(with: nil)
        isReady = false
        isPlaying = false
    }

    private static func resolveURL(_ raw: String) -> URL? {
        let resolved = VideoLibrary.resolve(raw) ?? raw
        if let url = URL(string: resolved), url.scheme != nil {
            if url.isFileURL, !FileManager.default.fileExists(atPath: url.path) { return nil }
            return url
        }
        let file = URL(fileURLWithPath: resolved)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, current / duration))
    }

    var currentLabel: String { Self.formatTime(current) }
    var durationLabel: String { Self.formatTime(duration) }
    var remainingLabel: String { "-\(Self.formatTime(max(0, duration - current)))" }

    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Shared video surface

struct LongFormPlayerSurface: View {
    @ObservedObject var model: LongFormPlayerModel
    var posterURL: String? = nil
    var posterData: Data? = nil
    var fill: Bool = false

    var body: some View {
        ZStack {
            Color.black
            if !model.isReady || model.failed {
                MediaImage(url: posterURL, data: posterData, cornerRadius: 0)
                    .opacity(model.failed ? 0.4 : 1)
            }
            // Keep the layer mounted whenever we have a current item — avoid black flashes on rotate.
            PlayerLayerView(
                player: model.player,
                videoGravity: fill ? .resizeAspectFill : .resizeAspect
            )
                .opacity(model.failed ? 0 : 1)
            if !model.isReady && !model.failed {
                ProgressView().tint(.white)
            }
            if model.failed {
                VStack(spacing: 8) {
                    Image(systemName: "play.slash.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Couldn't load video")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .background(Color.black)
        .clipped()
    }
}

// MARK: - Inline (portrait) chrome — YouTube watch page

struct FullscreenIgnoreSafeArea: ViewModifier {
    var enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.ignoresSafeArea()
        } else {
            content
        }
    }
}

struct LongFormInlineChrome: View {
    @ObservedObject var model: LongFormPlayerModel
    var onClose: () -> Void
    var onFullscreen: () -> Void
    var onPlayPrevious: () -> Void = {}
    var onPlayNext: () -> Void = {}

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.accumulateSkip(forward: false) }
                    .onTapGesture(count: 1) { model.toggleControls() }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.accumulateSkip(forward: true) }
                    .onTapGesture(count: 1) { model.toggleControls() }
            }

            inlineSkipFlash
                .allowsHitTesting(false)

            Color.black.opacity(model.controlsVisible ? 0.28 : 0)
                .allowsHitTesting(false)

            if model.controlsVisible {
                VStack(spacing: 0) {
                    HStack {
                        Button {} label: {
                            Image(systemName: "airplayvideo")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                    Spacer(minLength: 0)

                    HStack(spacing: 44) {
                        roundControl("backward.end.fill") {
                            onPlayPrevious()
                            model.showControls()
                        }
                        Button { model.togglePlay() } label: {
                            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 64, height: 64)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        roundControl("forward.end.fill") {
                            onPlayNext()
                            model.showControls()
                        }
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 10) {
                        Text(model.currentLabel)
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                        scrubber
                        Text(model.remainingLabel)
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                        Button(action: onFullscreen) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {} label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.controlsVisible)
    }

    @ViewBuilder
    private var inlineSkipFlash: some View {
        if model.skipFlashSeconds > 0 {
            HStack {
                if !model.skipFlashForward {
                    skipBadge
                    Spacer()
                } else {
                    Spacer()
                    skipBadge
                }
            }
            .padding(.horizontal, 28)
        }
    }

    private var skipBadge: some View {
        VStack(spacing: 4) {
            Image(systemName: model.skipFlashForward ? "goforward.10" : "gobackward.10")
                .font(.system(size: 22, weight: .semibold))
            Text(model.skipFlashForward ? "+\(model.skipFlashSeconds)" : "-\(model.skipFlashSeconds)")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(Circle().fill(Color.black.opacity(0.4)).frame(width: 88, height: 88))
    }

    private var scrubber: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.28)).frame(height: 3)
                Capsule().fill(Color.white).frame(width: max(3, w * model.progress), height: 3)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        model.showControls()
                        let p = min(1, max(0, value.location.x / max(w, 1)))
                        model.seek(to: p * model.duration)
                    }
            )
        }
        .frame(height: 20)
    }

    private func roundControl(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.black.opacity(0.4)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fullscreen chrome — YouTube structure, GojoGo identity

struct LongFormFullscreenChrome: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var model: LongFormPlayerModel
    let video: VideoItem
    var onExit: () -> Void
    var onPlayPrevious: () -> Void
    var onPlayNext: () -> Void

    @State private var autoplay = false

    private var nextVideo: VideoItem? {
        guard let i = app.videos.firstIndex(where: { $0.id == video.id }) else {
            return app.videos.first { $0.id != video.id }
        }
        let n = i + 1
        return n < app.videos.count ? app.videos[n] : app.videos.first
    }

    var body: some View {
        ZStack {
            // Double-tap zones (left rewind / right forward) + single-tap toggles chrome.
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        model.accumulateSkip(forward: false)
                    }
                    .onTapGesture(count: 1) {
                        model.toggleControls()
                    }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        model.accumulateSkip(forward: true)
                    }
                    .onTapGesture(count: 1) {
                        model.toggleControls()
                    }
            }

            skipFlashOverlay
                .allowsHitTesting(false)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.72),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.78)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .opacity(model.controlsVisible ? 1 : 0)
            .allowsHitTesting(false)

            if model.controlsVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    centerTransport
                    Spacer(minLength: 0)
                    bottomBar
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.controlsVisible)
        .statusBarHidden(true)
    }

    @ViewBuilder
    private var skipFlashOverlay: some View {
        if model.skipFlashSeconds > 0 {
            HStack {
                if !model.skipFlashForward {
                    skipBadge(seconds: model.skipFlashSeconds, forward: false)
                    Spacer()
                } else {
                    Spacer()
                    skipBadge(seconds: model.skipFlashSeconds, forward: true)
                }
            }
            .padding(.horizontal, 56)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
    }

    private func skipBadge(seconds: Int, forward: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: forward ? "goforward.10" : "gobackward.10")
                .font(.system(size: 28, weight: .semibold))
            Text(forward ? "+\(seconds)" : "-\(seconds)")
                .font(.system(size: 18, weight: .bold).monospacedDigit())
        }
        .foregroundStyle(GGColor.textPrimary)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(Circle().fill(Color.black.opacity(0.35)).frame(width: 110, height: 110))
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Wordmark(size: 15)
                Text(video.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(2)
                Text("@\(video.channel)")
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textSecondary)
            }
            .allowsHitTesting(false)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                Button {
                    autoplay.toggle()
                    model.showControls()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Capsule()
                            .fill(autoplay ? GGColor.white : Color.white.opacity(0.22))
                            .frame(width: 28, height: 16)
                            .overlay(alignment: autoplay ? .trailing : .leading) {
                                Circle()
                                    .fill(autoplay ? Color.black : Color.white)
                                    .frame(width: 12, height: 12)
                                    .padding(2)
                            }
                    }
                    .foregroundStyle(GGColor.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassCapsule(fillOpacity: 0.14, borderOpacity: 0.16)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                glassIcon("airplayvideo")
                glassIcon("captions.bubble")
                glassIcon("gearshape")
            }
        }
    }

    private var centerTransport: some View {
        HStack(spacing: 44) {
            transportButton("backward.end.fill", enabled: app.videos.count > 1) {
                onPlayPrevious()
                model.showControls()
            }
            Button {
                model.togglePlay()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .overlay(Circle().strokeBorder(GGColor.hairline, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(SoftPressStyle())
            transportButton("forward.end.fill", enabled: app.videos.count > 1) {
                onPlayNext()
                model.showControls()
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(model.currentLabel) / \(model.durationLabel)")
                    .font(.ggMono(12, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassCapsule(fillOpacity: 0.14, borderOpacity: 0.14)
                    .allowsHitTesting(false)

                Spacer()

                Button(action: onExit) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .overlay(Circle().strokeBorder(GGColor.hairline, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            gojoScrubber

            HStack(spacing: 0) {
                HStack(spacing: 18) {
                    fsAction(video.liked ? "hand.thumbsup.fill" : "hand.thumbsup") {
                        app.toggleVideoLike(video.id)
                    }
                    fsAction("hand.thumbsdown")
                    fsAction("bubble.right")
                    fsAction(video.saved ? "bookmark.fill" : "bookmark") {
                        app.toggleVideoSave(video.id)
                    }
                    fsAction("arrowshape.turn.up.right")
                    Button {
                        model.showControls()
                        onExit()
                        app.openMadeleineWhileWatching()
                    } label: {
                        MiniOrb(size: 28, glow: true)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    fsAction("ellipsis")
                }

                Spacer(minLength: 12)

                if let next = nextVideo {
                    Button {
                        onPlayNext()
                    } label: {
                        HStack(spacing: 10) {
                            Text("Up next")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(GGColor.textPrimary)
                            MediaImage(url: next.thumbURL, data: next.thumbData, cornerRadius: 6)
                                .frame(width: 52, height: 30)
                                .clipped()
                        }
                        .padding(.leading, 14)
                        .padding(.trailing, 8)
                        .padding(.vertical, 7)
                        .glassCapsule(fillOpacity: 0.14, borderOpacity: 0.16)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(SoftPressStyle())
                }
            }
        }
    }

    private var gojoScrubber: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22)).frame(height: 3)
                Capsule()
                    .fill(GGColor.white)
                    .frame(width: max(4, w * model.progress), height: 3)
                Circle()
                    .fill(GGColor.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: max(0, w * model.progress - 7))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        model.showControls()
                        let p = min(1, max(0, value.location.x / max(w, 1)))
                        model.seek(to: p * model.duration)
                    }
            )
        }
        .frame(height: 22)
    }

    private func transportButton(_ icon: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary.opacity(enabled ? 1 : 0.35))
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .overlay(Circle().strokeBorder(GGColor.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(SoftPressStyle())
        .disabled(!enabled)
    }

    private func glassIcon(_ name: String) -> some View {
        Button {
            model.showControls()
        } label: {
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .overlay(Circle().strokeBorder(GGColor.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func fsAction(_ icon: String, action: @escaping () -> Void = {}) -> some View {
        Button {
            model.showControls()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
