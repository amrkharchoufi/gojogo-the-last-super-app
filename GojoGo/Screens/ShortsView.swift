import SwiftUI

struct ShortsView: View {
    @EnvironmentObject var app: AppState
    @State private var index = 0
    @State private var dragY: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                ForEach(Array(app.shorts.enumerated()), id: \.element.id) { i, short in
                    ShortCard(shortID: short.id, isActive: i == index)
                        .frame(width: geo.size.width, height: h)
                        .offset(y: CGFloat(i - index) * h + dragY)
                        .opacity(abs(i - index) <= 1 ? 1 : 0)
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture()
                    .onChanged { v in
                        guard abs(v.translation.height) > abs(v.translation.width) else { return }
                        dragY = v.translation.height
                    }
                    .onEnded { v in
                        guard abs(v.translation.height) > abs(v.translation.width) else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { dragY = 0 }
                            return
                        }
                        let threshold: CGFloat = 70
                        var newIndex = index
                        if v.translation.height < -threshold {
                            newIndex = min(index + 1, app.shorts.count - 1)
                        } else if v.translation.height > threshold {
                            newIndex = max(index - 1, 0)
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            index = newIndex
                            dragY = 0
                        }
                    })
        }
        .ignoresSafeArea()
        .onAppear { jumpToFocusedShort() }
        .onChange(of: app.shorts.first?.id) { _, _ in
            // New publishes insert at 0 — jump to the fresh short.
            if app.focusedShortID == nil {
                index = 0
                dragY = 0
            }
        }
        .onChange(of: app.focusedShortID) { _, _ in
            jumpToFocusedShort()
        }
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
    @State private var heartTrigger = 0
    @State private var heartBounce = false
    @State private var isPaused = false

    private var short: Short {
        app.shorts.first(where: { $0.id == shortID })
            ?? Short(channel: "", subscribers: "", caption: "", gradient: [])
    }

    var body: some View {
        ZStack {
            // Full-bleed media — poster underneath, video on the active card
            ZStack {
                MediaImage(url: short.imageURL, data: short.imageData, cornerRadius: 0)
                if let videoURL = short.videoURL, !videoURL.isEmpty, isActive {
                    ShortVideoPlayer(urlString: videoURL, isActive: !isPaused)
                }
            }
            .ignoresSafeArea()
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
                guard short.videoURL != nil, !(short.videoURL?.isEmpty ?? true) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    isPaused.toggle()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            HeartBurstOverlay(trigger: heartTrigger)

            if isPaused {
                Image(systemName: "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(Circle().fill(Color.black.opacity(0.4)))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .allowsHitTesting(false)
            }

            // Top chrome
            VStack {
                HStack(alignment: .center) {
                    Wordmark(size: 19)
                        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
                    Spacer()
                    WatchSegments(selection: $app.watchSubFeed)
                }
                .padding(.horizontal, 16)
                .padding(.top, 58)
                Spacer()
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
                    railAction(icon: "message", tint: .white, label: nil) {}
                    railAction(icon: "paperplane", tint: .white, label: nil) {}
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

            // Caption + channel
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
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
                                .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
                            Text(short.subscribers)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.75))
                                .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                        }

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
        }
        .clipped()
        .onChange(of: isActive) { _, active in
            if !active { isPaused = false }
        }
    }

    private func railAction(icon: String, tint: Color, label: String?,
                            scale: CGFloat = 1,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
        .buttonStyle(SoftPressStyle())
    }
}
