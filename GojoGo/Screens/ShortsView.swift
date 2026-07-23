import SwiftUI
import AVFoundation
import UIKit

struct ShortsView: View {
    @EnvironmentObject var app: AppState
    @State private var index = 0
    @State private var dragY: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let h = max(geo.size.height, 1)
            let w = geo.size.width

            ZStack {
                // Immersive black behind actual video; theme background for the
                // empty state so light mode doesn't read as a broken black screen.
                baseBackground.ignoresSafeArea()

                if app.shorts.isEmpty {
                    GGEmptyState(
                        icon: "rectangle.stack",
                        title: "No Shorts yet",
                        message: "Vertical clips will appear here when people start posting."
                    )
                } else {
                    // Only keep current ±1 mounted for smooth preload without thrashing.
                    ForEach(visibleIndices, id: \.self) { i in
                        let short = app.shorts[i]
                        ShortCard(
                            shortID: short.id,
                            isActive: i == index,
                            isSettled: dragY == 0 && i == index
                        )
                        .frame(width: w, height: h)
                        .offset(y: CGFloat(i - index) * h + dragY)
                    }
                }
            }
            .frame(width: w, height: h)
            .clipped()
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in
                        guard !app.shorts.isEmpty else { return }
                        guard abs(v.translation.height) > abs(v.translation.width) * 0.85 else { return }
                        // Rubber-band at ends.
                        var ty = v.translation.height
                        if index == 0, ty > 0 { ty *= 0.35 }
                        if index >= app.shorts.count - 1, ty < 0 { ty *= 0.35 }
                        dragY = ty
                    }
                    .onEnded { v in
                        guard !app.shorts.isEmpty else {
                            dragY = 0
                            return
                        }
                        guard abs(v.translation.height) > abs(v.translation.width) * 0.85 else {
                            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
                                dragY = 0
                            }
                            return
                        }
                        let projected = v.predictedEndTranslation.height
                        let threshold = h * 0.18
                        var newIndex = index
                        if projected < -threshold || v.translation.height < -threshold {
                            newIndex = min(index + 1, app.shorts.count - 1)
                        } else if projected > threshold || v.translation.height > threshold {
                            newIndex = max(index - 1, 0)
                        }
                        if newIndex != index {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.9)) {
                            index = newIndex
                            dragY = 0
                        }
                    }
            )

            // Single chrome layer — avoids duplicate pills mid-swipe.
            VStack {
                HStack(alignment: .center) {
                    Wordmark(size: 19)
                        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
                    Spacer()
                    WatchSegments(selection: $app.watchSubFeed)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
            .allowsHitTesting(true)
        }
        .ignoresSafeArea(edges: .bottom)
        .background(baseBackground.ignoresSafeArea())
        .onAppear { jumpToFocusedShort() }
        .onChange(of: app.shorts.first?.id) { _, _ in
            if app.focusedShortID == nil {
                index = 0
                dragY = 0
            }
        }
        .onChange(of: app.focusedShortID) { _, _ in
            jumpToFocusedShort()
        }
        .onChange(of: app.shorts.count) { _, _ in
            index = min(index, max(app.shorts.count - 1, 0))
        }
    }

    /// Black for the immersive video feed; theme background when there's nothing to play.
    private var baseBackground: Color {
        app.shorts.isEmpty ? GGColor.bg : .black
    }

    private var visibleIndices: [Int] {
        guard !app.shorts.isEmpty else { return [] }
        let lo = max(0, index - 1)
        let hi = min(app.shorts.count - 1, index + 1)
        return Array(lo...hi)
    }

    private func jumpToFocusedShort() {
        guard let id = app.focusedShortID,
              let i = app.shorts.firstIndex(where: { $0.id == id }) else { return }
        index = i
        dragY = 0
        app.focusedShortID = nil
    }
}

struct ShortCard: View {
    @EnvironmentObject var app: AppState
    let shortID: UUID
    var isActive: Bool = true
    /// True only for the settled current page — used to hide poster once video owns the frame.
    var isSettled: Bool = true
    @State private var heartTrigger = 0
    @State private var heartBounce = false
    @State private var isPaused = false
    /// Video width/height once known. `nil` until probed (assume Reels portrait).
    @State private var videoAspect: CGFloat?

    private var short: Short {
        app.shorts.first(where: { $0.id == shortID })
            ?? Short(channel: "", subscribers: "", caption: "", gradient: [])
    }

    private var commentCount: Int {
        app.commentsByPost[shortID]?.count ?? 0
    }

    private var hasVideo: Bool {
        guard let u = short.videoURL else { return false }
        return !u.isEmpty
    }

    /// Landscape (e.g. 16:9) → letterbox. Portrait / unknown → full-bleed Reels fill.
    private var isLandscapeVideo: Bool {
        guard let aspect = videoAspect else { return false }
        return aspect > 1.15
    }

    var body: some View {
        GeometryReader { geo in
            let mediaSize = mediaFrame(in: geo.size)

            ZStack {
                Color.black

                Group {
                    if hasVideo {
                        MediaImage(url: short.imageURL, data: short.imageData, cornerRadius: 0)
                            .frame(width: mediaSize.width, height: mediaSize.height)
                            .clipped()
                            .opacity(isActive && !isPaused ? 0 : 1)
                            .animation(.easeOut(duration: 0.15), value: isActive)

                        ShortVideoPlayer(
                            urlString: short.videoURL!,
                            isActive: isActive && !isPaused,
                            isMuted: app.shortsMuted,
                            videoGravity: isLandscapeVideo ? .resizeAspect : .resizeAspectFill
                        )
                        .frame(width: mediaSize.width, height: mediaSize.height)
                        .clipped()
                    } else {
                        MediaImage(url: short.imageURL, data: short.imageData, cornerRadius: 0)
                            .frame(width: mediaSize.width, height: mediaSize.height)
                            .clipped()
                    }
                }
                .frame(width: mediaSize.width, height: mediaSize.height)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Soft bottom/top scrims for readable chrome.
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.45), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 120)
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 220)
                }
                .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
                    .overlay(
                        ShortTapOverlay(
                            onSingleTap: {
                                guard hasVideo, isActive else { return }
                                togglePauseInstant()
                            },
                            onDoubleTap: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                // Keep playing on double-tap like (Instagram).
                                if isPaused { setPaused(false) }
                                _ = app.likeShort(shortID)
                                heartTrigger += 1
                                heartBounce = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    heartBounce = false
                                }
                            }
                        )
                    )

                HeartBurstOverlay(trigger: heartTrigger)

                if isPaused && isActive {
                    VStack(spacing: 16) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeOut(duration: 0.15)) {
                                app.toggleShortsMute()
                            }
                        } label: {
                            Image(systemName: app.shortsMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                        }
                        .buttonStyle(.plain)

                        Image(systemName: "play.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(18)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                            .allowsHitTesting(false)
                    }
                    .transition(.opacity.combined(with: .scale(0.94)))
                }

                // Right action rail
                VStack {
                    Spacer()
                    VStack(spacing: 18) {
                        railAction(
                            icon: short.liked ? "heart.fill" : "heart",
                            tint: .white,
                            label: formatCount(short.likeCount),
                            scale: heartBounce ? 1.28 : 1
                        ) {
                            let wasLiked = short.liked
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                                app.toggleShortLike(shortID)
                            }
                            if !wasLiked {
                                heartTrigger += 1
                                heartBounce = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    heartBounce = false
                                }
                            }
                        }
                        railAction(
                            icon: "message", tint: .white,
                            label: commentCount > 0 ? formatCount(commentCount) : nil
                        ) {
                            app.openComments(for: shortID)
                        }
                        ShareLink(item: app.shortShareURL(for: shortID)) {
                            railLabel(icon: "paperplane", tint: .white, label: nil)
                        }
                        .buttonStyle(SoftPressStyle())
                        railAction(
                            icon: short.bookmarked ? "bookmark.fill" : "bookmark",
                            tint: short.bookmarked ? GGColor.blue : .white,
                            label: nil
                        ) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                                app.toggleShortBookmark(shortID)
                            }
                        }
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 168)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .opacity(isSettled || isActive ? 1 : 0.35)

                // Caption + channel
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Button {
                                app.openUserProfile(handle: short.channel,
                                                    avatarURL: short.imageURL,
                                                    avatarGradient: short.gradient)
                            } label: {
                                HStack(spacing: 10) {
                                    UserAvatar(size: 40,
                                               letter: String(short.channel.prefix(1)).uppercased(),
                                               ring: true,
                                               imageURL: short.imageURL,
                                               imageData: short.imageData)
                                        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(short.channel)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Text(short.subscribers)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.75))
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    app.toggleShortFollow(shortID)
                                }
                            } label: {
                                Text(short.following ? "Following" : "Follow")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .glassCapsule(interactive: true)
                            }
                            .buttonStyle(SoftPressStyle())
                        }

                        Text(short.caption)
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
                            .frame(maxWidth: 260, alignment: .leading)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 72)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 128)
                }
                .opacity(isSettled || isActive ? 1 : 0.35)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear { probeVideoAspect() }
        .onChange(of: short.videoURL) { _, _ in
            videoAspect = nil
            probeVideoAspect()
        }
        .onChange(of: isActive) { _, active in
            if !active { isPaused = false }
        }
        .animation(.easeOut(duration: 0.14), value: isPaused)
    }

    private func togglePauseInstant() {
        setPaused(!isPaused)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func setPaused(_ paused: Bool) {
        isPaused = paused
        guard let url = short.videoURL, !url.isEmpty else { return }
        ShortVideoPlayerCache.setPlaybackPaused(urlString: url, paused: paused)
    }

    /// Portrait → fill the phone. Landscape → keep native ratio (letterboxed).
    private func mediaFrame(in size: CGSize) -> CGSize {
        guard isLandscapeVideo, let aspect = videoAspect, aspect > 0 else {
            return size
        }
        // Fit landscape inside the screen: full width, height from aspect.
        let fittedH = size.width / aspect
        if fittedH <= size.height {
            return CGSize(width: size.width, height: fittedH)
        }
        // Ultra-wide fallback: fit by height.
        return CGSize(width: size.height * aspect, height: size.height)
    }

    private func probeVideoAspect() {
        guard let raw = short.videoURL, !raw.isEmpty else { return }
        let resolved = VideoLibrary.resolve(raw) ?? SampleData.repairedVideoURL(raw) ?? raw
        guard let url = URL(string: resolved) ?? URL(string: raw) else { return }
        let fileURL: URL = {
            if url.scheme == nil { return URL(fileURLWithPath: resolved) }
            return url
        }()

        Task {
            let asset = AVURLAsset(url: fileURL)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
            async let natural = track.load(.naturalSize)
            async let transform = track.load(.preferredTransform)
            guard let size = try? await natural,
                  let xf = try? await transform else { return }
            let rendered = size.applying(xf)
            let w = abs(rendered.width)
            let h = abs(rendered.height)
            guard w > 1, h > 1 else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    videoAspect = w / h
                }
            }
        }
    }

    private func railAction(icon: String, tint: Color, label: String?,
                            scale: CGFloat = 1,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            railLabel(icon: icon, tint: tint, label: label, scale: scale)
        }
        .buttonStyle(SoftPressStyle())
    }

    private func railLabel(icon: String, tint: Color, label: String?,
                           scale: CGFloat = 1) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(tint)
                .scaleEffect(scale)
                .animation(.spring(response: 0.28, dampingFraction: 0.55), value: scale)
                .frame(width: 46, height: 46)
                .background {
                    Circle().fill(.ultraThinMaterial)
                    Circle().fill(Color.black.opacity(0.25))
                }
                .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)

            if let label {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
            }
        }
    }
}

// MARK: - Instant single-tap (no double-tap delay)

/// UIKit taps: single fires immediately; double also fires (caller resumes + likes).
private struct ShortTapOverlay: UIViewRepresentable {
    var onSingleTap: () -> Void
    var onDoubleTap: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let double = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDouble(_:))
        )
        double.numberOfTapsRequired = 2

        let single = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingle(_:))
        )
        single.numberOfTapsRequired = 1
        // Do not require double to fail — that adds ~300ms pause latency.

        view.addGestureRecognizer(double)
        view.addGestureRecognizer(single)
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onDoubleTap = onDoubleTap
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onDoubleTap = onDoubleTap
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var onSingleTap: () -> Void = {}
        var onDoubleTap: () -> Void = {}

        @objc func handleSingle(_ g: UITapGestureRecognizer) {
            guard g.state == .ended else { return }
            onSingleTap()
        }

        @objc func handleDouble(_ g: UITapGestureRecognizer) {
            guard g.state == .ended else { return }
            onDoubleTap()
        }
    }
}
