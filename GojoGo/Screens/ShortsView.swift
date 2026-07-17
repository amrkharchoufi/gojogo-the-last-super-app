import SwiftUI
import AVFoundation

struct ShortsView: View {
    @EnvironmentObject var app: AppState
    @State private var index = 0
    @State private var dragY: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let h = max(geo.size.height, 1)
            let w = geo.size.width

            ZStack {
                Color.black.ignoresSafeArea()

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
            .frame(width: w, height: h)
            .clipped()
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in
                        guard abs(v.translation.height) > abs(v.translation.width) * 0.85 else { return }
                        // Rubber-band at ends.
                        var ty = v.translation.height
                        if index == 0, ty > 0 { ty *= 0.35 }
                        if index >= app.shorts.count - 1, ty < 0 { ty *= 0.35 }
                        dragY = ty
                    }
                    .onEnded { v in
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
        .background(Color.black.ignoresSafeArea())
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

    var body: some View {
        ZStack {
            Color.black

            // Poster only as fallback under video (inactive / buffering). Never the hero once video is active.
            if hasVideo {
                MediaImage(url: short.imageURL, data: short.imageData, cornerRadius: 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .opacity(isActive && !isPaused ? 0 : 1)
                    .animation(.easeOut(duration: 0.15), value: isActive)

                ShortVideoPlayer(
                    urlString: short.videoURL!,
                    isActive: isActive && !isPaused,
                    isMuted: app.feedVideosMuted,
                    videoGravity: .resizeAspectFill
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            } else {
                MediaImage(url: short.imageURL, data: short.imageData, cornerRadius: 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }

            // Soft bottom/top scrims for readable chrome — no layout stretch.
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
                .onTapGesture(count: 2) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    _ = app.likeShort(shortID)
                    heartTrigger += 1
                    heartBounce = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        heartBounce = false
                    }
                }
                .onTapGesture(count: 1) {
                    guard hasVideo else { return }
                    isPaused.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

            HeartBurstOverlay(trigger: heartTrigger)

            if isPaused && isActive {
                Image(systemName: "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(Circle().fill(Color.black.opacity(0.4)))
                    .allowsHitTesting(false)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onChange(of: isActive) { _, active in
            if !active { isPaused = false }
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
