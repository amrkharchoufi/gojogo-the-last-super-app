import SwiftUI
import AVFoundation
import UIKit

// MARK: - Frame content

/// Renders one frame's media — a photo, a video, or a text card — with its
/// overlays on top. Shared by the composer (so what you compose is literally
/// what gets played) and the viewer.
struct StoryFrameCanvas: View {
    let frame: StoryFrame
    var isActive: Bool = true
    var isPaused: Bool = false
    var isMuted: Bool = false
    /// Video reports its own playback position; stills are timed by the viewer.
    var videoProgress: Binding<Double>? = nil
    var onVideoFinished: () -> Void = {}
    var showsMusicSticker: Bool = true
    /// Lifted in the viewer so the sticker clears the reply bar.
    var musicStickerBottomInset: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch frame.kind {
                case .text:
                    textCard(size: geo.size)
                case .video:
                    videoBody
                case .image:
                    MediaImage(url: frame.imageURL, data: frame.imageData, cornerRadius: 0)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }

                StoryOverlayLayer(overlays: frame.overlays, size: geo.size)
                    .allowsHitTesting(false)

                // Attribution for the sound, above the author's own overlays
                // and never draggable.
                if let music = frame.music, showsMusicSticker {
                    StoryMusicSticker(music: music, isPlaying: !isPaused)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .bottomLeading)
                        .padding(.leading, 14)
                        .padding(.bottom, musicStickerBottomInset)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    @ViewBuilder
    private var videoBody: some View {
        if let source = frame.playableVideo {
            StoryVideoPlayer(
                source: source,
                posterURL: frame.imageURL,
                posterData: frame.imageData,
                isActive: isActive,
                isPaused: isPaused,
                // A frame with a sound plays its video silently — two audio
                // tracks at once is noise, and the chosen song wins.
                isMuted: isMuted || frame.music != nil,
                progress: videoProgress,
                onFinished: onVideoFinished)
        } else {
            MediaImage(url: frame.imageURL, data: frame.imageData, cornerRadius: 0)
        }
    }

    private func textCard(size: CGSize) -> some View {
        ZStack {
            frame.background.gradient
            Text(frame.caption ?? "")
                .font(.system(size: textSize(for: frame.caption, width: size.width), weight: .semibold))
                .foregroundStyle(frame.background.foreground)
                .multilineTextAlignment(.center)
                .lineLimit(12)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, size.width * 0.12)
        }
    }

    /// Short text gets the big treatment, long text steps down — the same
    /// instinct as Instagram's auto-sizing text card.
    private func textSize(for text: String?, width: CGFloat) -> CGFloat {
        let count = text?.count ?? 0
        let fraction: CGFloat = switch count {
        case ..<25: 0.11
        case ..<80: 0.075
        case ..<200: 0.055
        default: 0.042
        }
        return width * fraction
    }
}

// MARK: - Overlays

/// Draws text/sticker overlays from their normalized spec, so a frame composed
/// on any device lands in the same place on every other one.
struct StoryOverlayLayer: View {
    let overlays: [StoryOverlay]
    let size: CGSize

    var body: some View {
        ForEach(overlays) { overlay in
            content(overlay)
                .rotationEffect(.radians(overlay.rotation))
                .scaleEffect(overlay.scale)
                .position(x: overlay.x * size.width, y: overlay.y * size.height)
        }
    }

    @ViewBuilder
    private func content(_ overlay: StoryOverlay) -> some View {
        switch overlay.kind {
        case .text:
            Text(overlay.text ?? "")
                .font(.system(size: overlay.fontScale * size.width, weight: .bold))
                .foregroundStyle(overlay.isLight ? Color.white : Color(hex: "111114"))
                .shadow(color: .black.opacity(overlay.isLight ? 0.4 : 0), radius: 8, y: 2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: size.width * 0.86)
        case .sticker:
            stickerImage(overlay)
                .frame(width: overlay.fontScale * size.width)
        }
    }

    @ViewBuilder
    private func stickerImage(_ overlay: StoryOverlay) -> some View {
        if let data = overlay.imageData, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFit()
        } else if let url = overlay.imageURL {
            MediaImage(url: url, cornerRadius: 0)
                .aspectRatio(1, contentMode: .fit)
        } else {
            Color.clear
        }
    }
}

// MARK: - Video

/// Play-once video for a story frame.
///
/// Deliberately not `ShortVideoPlayer`: that one loops forever and shares one
/// `AVPlayer` per URL across the app, both of which are wrong here — a story
/// frame plays exactly once and then hands the screen to the next frame.
struct StoryVideoPlayer: View {
    let source: String
    var posterURL: String?
    var posterData: Data?
    var isActive: Bool
    var isPaused: Bool
    var isMuted: Bool
    var progress: Binding<Double>?
    var onFinished: () -> Void

    @StateObject private var controller = StoryVideoController()

    var body: some View {
        ZStack {
            Color.black
            if !controller.isReady {
                MediaImage(url: posterURL, data: posterData, cornerRadius: 0)
            }
            StoryVideoLayer(player: controller.player)
                .opacity(controller.isReady ? 1 : 0)
        }
        .onAppear {
            controller.onFinished = onFinished
            controller.onProgress = { progress?.wrappedValue = $0 }
            controller.load(source, muted: isMuted)
            controller.setPlaying(isActive && !isPaused)
        }
        .onChange(of: source) { _, new in
            controller.load(new, muted: isMuted)
            controller.setPlaying(isActive && !isPaused)
        }
        .onChange(of: isPaused) { _, paused in controller.setPlaying(isActive && !paused) }
        .onChange(of: isActive) { _, active in controller.setPlaying(active && !isPaused) }
        .onChange(of: isMuted) { _, muted in controller.setMuted(muted) }
        .onDisappear { controller.teardown() }
    }
}

@MainActor
final class StoryVideoController: ObservableObject {

    @Published var isReady = false

    let player = AVPlayer()
    var onFinished: () -> Void = {}
    var onProgress: (Double) -> Void = { _ in }

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var readyObserver: NSKeyValueObservation?
    private var loadedSource: String?

    func load(_ source: String, muted: Bool) {
        guard loadedSource != source else { return }
        teardown()
        loadedSource = source
        guard let url = Self.resolve(source) else { return }

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.isMuted = muted
        Self.activateAudioSession()

        readyObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            Task { @MainActor in self?.isReady = true }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onProgress(1)
                self?.onFinished()
            }
        }
        // 20 Hz is enough to keep a 3px progress bar looking continuous.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            guard let self, let duration = self.player.currentItem?.duration.seconds,
                  duration.isFinite, duration > 0 else { return }
            Task { @MainActor in self.onProgress(min(1, time.seconds / duration)) }
        }
    }

    func setPlaying(_ playing: Bool) {
        if playing {
            player.play()
        } else {
            player.pause()
        }
    }

    func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }

    func restart() {
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func teardown() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        readyObserver?.invalidate()
        readyObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isReady = false
        loadedSource = nil
    }

    /// Accepts an https URL, a `gojovideo:` library ref, or a local file path —
    /// a frame plays from disk while its upload is still in flight.
    private static func resolve(_ raw: String) -> URL? {
        let resolved = VideoLibrary.resolve(raw) ?? raw
        if let url = URL(string: resolved), url.scheme != nil {
            if url.isFileURL, !FileManager.default.fileExists(atPath: url.path) { return nil }
            return url
        }
        let file = URL(fileURLWithPath: resolved)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    private static func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

/// Bare `AVPlayerLayer` host — `VideoPlayer` would bring system controls a
/// story must not show.
struct StoryVideoLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}
