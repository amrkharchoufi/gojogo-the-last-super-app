import SwiftUI
import UIKit

/// YouTube-style long-form player. Madeleine opens as a bottom drawer under the video.
struct WatchingMadeleineView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var playerModel = LongFormPlayerModel()

    private var video: VideoItem? { app.watchingVideo }

    var body: some View {
        GeometryReader { geo in
            let shortSide = min(geo.size.width, geo.size.height)
            let inlineHeight = shortSide * 9 / 16
            // Prefer the real screen size in fullscreen so home-indicator inset can't leave a bottom gap.
            let screen = UIScreen.main.bounds
            let fullW = max(screen.width, screen.height)
            let fullH = min(screen.width, screen.height)
            let surfaceW = playerModel.isFullscreen ? fullW : geo.size.width
            let surfaceH = playerModel.isFullscreen ? fullH : inlineHeight

            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                LongFormPlayerSurface(
                    model: playerModel,
                    posterURL: video?.thumbURL,
                    posterData: video?.thumbData,
                    fill: playerModel.isFullscreen
                )
                .frame(width: surfaceW, height: max(surfaceH, 1))
                .clipped()
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    // Portrait: pin to the top player slot. Fullscreen: fill the screen.
                    alignment: playerModel.isFullscreen ? .center : .top
                )
                .modifier(FullscreenIgnoreSafeArea(enabled: playerModel.isFullscreen))
                .allowsHitTesting(false)

                if playerModel.isFullscreen, let video {
                    LongFormFullscreenChrome(
                        model: playerModel,
                        video: video,
                        onExit: { playerModel.exitFullscreen() },
                        onPlayPrevious: {
                            guard let prev = previousVideo(from: video.id) else { return }
                            app.playVideo(prev.id)
                            playerModel.load(urlString: prev.videoURL, autoplay: true)
                        },
                        onPlayNext: {
                            guard let next = nextVideo(from: video.id) else { return }
                            app.playVideo(next.id)
                            playerModel.load(urlString: next.videoURL, autoplay: true)
                        }
                    )
                    .frame(width: surfaceW, height: surfaceH)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                } else {
                    VStack(spacing: 0) {
                        LongFormInlineChrome(
                            model: playerModel,
                            onClose: { app.closeWatching() },
                            onFullscreen: { playerModel.enterFullscreen() },
                            onPlayPrevious: {
                                guard let v = video, let prev = previousVideo(from: v.id) else { return }
                                app.playVideo(prev.id)
                                playerModel.load(urlString: prev.videoURL, autoplay: true)
                            },
                            onPlayNext: {
                                guard let v = video, let next = nextVideo(from: v.id) else { return }
                                app.playVideo(next.id)
                                playerModel.load(urlString: next.videoURL, autoplay: true)
                            }
                        )
                        .frame(width: geo.size.width, height: inlineHeight)

                        ZStack(alignment: .bottom) {
                            videoDetailsScroll
                                .opacity(app.watchingWithMadeleine ? 0.35 : 1)
                                .allowsHitTesting(!app.watchingWithMadeleine)

                            if app.watchingWithMadeleine {
                                Color.black.opacity(0.25)
                                    .ignoresSafeArea(edges: .bottom)
                                    .onTapGesture { dismissMadeleineDrawer() }
                                    .transition(.opacity)

                                madeleineDrawer
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(GGColor.bg)
                        .clipped()
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(GGColor.bg.ignoresSafeArea())
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: app.watchingWithMadeleine)
        .preferredColorScheme(.dark)
        .onAppear {
            playerModel.load(urlString: video?.videoURL, autoplay: true)
            playerModel.showControls()
        }
        .onChange(of: app.watchingVideoID) { _, _ in
            playerModel.load(urlString: video?.videoURL, autoplay: true)
        }
        .onChange(of: playerModel.isFullscreen) { _, fullscreen in
            if !fullscreen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    playerModel.player.play()
                }
            }
        }
        .onDisappear {
            playerModel.shutdown()
        }
    }

    private func nextVideo(from id: UUID) -> VideoItem? {
        guard let i = app.videos.firstIndex(where: { $0.id == id }) else {
            return app.videos.first { $0.id != id }
        }
        let next = i + 1
        return next < app.videos.count ? app.videos[next] : app.videos.first
    }

    private func previousVideo(from id: UUID) -> VideoItem? {
        guard let i = app.videos.firstIndex(where: { $0.id == id }) else { return nil }
        let prev = i - 1
        return prev >= 0 ? app.videos[prev] : app.videos.last
    }

    // MARK: - YouTube details

    private var videoDetailsScroll: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(video?.title ?? "Untitled")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(video?.meta ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                HStack(spacing: 12) {
                    Button {
                        if let channel = video?.channel {
                            app.openUserProfile(handle: channel, avatarURL: video?.thumbURL)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            UserAvatar(size: 40,
                                       letter: String((video?.channel ?? "?").prefix(1)),
                                       imageURL: video?.thumbURL)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(video?.channel ?? "channel")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(app.subscriberLabel(for: video?.channel ?? "channel"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(GGColor.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        if let channel = video?.channel {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeOut(duration: 0.2)) {
                                app.toggleSubscribe(channel)
                            }
                        }
                    } label: {
                        let subscribed = app.isSubscribed(video?.channel ?? "")
                        Text(subscribed ? "Subscribed" : "Subscribe")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(subscribed ? .white : .black)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(subscribed ? Color.white.opacity(0.14) : Color.white))
                    }
                    .buttonStyle(SoftPressStyle())
                }
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if let id = video?.id {
                            actionChip(
                                icon: (video?.liked == true) ? "hand.thumbsup.fill" : "hand.thumbsup",
                                title: formatCount(video?.likes ?? 0)
                            ) { app.toggleVideoLike(id) }
                            actionChip(
                                icon: app.isVideoDisliked(id) ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                                title: ""
                            ) { app.toggleVideoDislike(id) }
                            actionChip(
                                icon: (video?.saved == true) ? "bookmark.fill" : "bookmark",
                                title: video?.saved == true ? "Saved" : "Save"
                            ) { app.toggleVideoSave(id) }
                            ShareLink(item: app.videoShareURL(for: id),
                                      subject: Text(video?.title ?? "GojoGo video")) {
                                chipLabel(icon: "arrowshape.turn.up.right", title: "Share")
                            }
                            .buttonStyle(SoftPressStyle())
                            actionChip(
                                icon: app.isVideoDownloaded(id) ? "checkmark.circle.fill" : "arrow.down.circle",
                                title: app.isVideoDownloaded(id) ? "Downloaded" : "Download"
                            ) { app.toggleVideoDownload(id) }
                            actionChip(icon: "flag", title: "Report") {
                                app.reportVideo(id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Button {
                    app.openMadeleineWhileWatching()
                } label: {
                    HStack(spacing: 12) {
                        MiniOrb(size: 36, glow: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Watch with Madeleine")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Ask questions while the video plays")
                                .font(.system(size: 12))
                                .foregroundStyle(GGColor.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(GGColor.textTertiary)
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 18, interactive: true)
                }
                .buttonStyle(SoftPressStyle())
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(descriptionCopy)
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineSpacing(3)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Up next")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)

                    ForEach(relatedVideos) { item in
                        Button {
                            app.playVideo(item.id)
                        } label: {
                            relatedRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color.black)
    }

    // MARK: - Madeleine drawer (under video)

    private var madeleineDrawer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                UserAvatar(size: 30,
                           letter: String((video?.channel ?? "S").prefix(1)),
                           imageURL: video?.thumbURL)
                VStack(alignment: .leading, spacing: 1) {
                    Text(video?.title ?? "Untitled")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text((video?.channel ?? "channel") + " · watching")
                        .font(.system(size: 11))
                        .foregroundStyle(GGColor.textTertiary)
                }
                Spacer(minLength: 8)
                if let id = video?.id {
                    Button { app.toggleVideoLike(id) } label: {
                        Image(systemName: (video?.liked == true) ? "heart.fill" : "heart")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 36, height: 36)
                            .glassCapsule()
                    }
                }
                Button { dismissMadeleineDrawer() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 36, height: 36)
                        .glassCapsule()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                HStack(spacing: 8) {
                    MiniOrb(size: 22, glow: true)
                    Text("Madeleine")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("watching with you")
                        .font(.ggMono(11, .regular))
                        .foregroundStyle(GGColor.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(app.watchingChat) { msg in
                                ChatBubble(message: msg).id(msg.id)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: app.watchingChat.count) { _, _ in
                        if let last = app.watchingChat.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 8) {
                    TextField("Ask about this video…", text: $app.watchingDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                        .overlay(Capsule().strokeBorder(GGColor.hairline, lineWidth: 1))

                    Button {
                        app.sendWatchingChat()
                    } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.white))
                    }
                    .buttonStyle(SoftPressStyle())
                    .disabled(app.watchingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(app.watchingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .liquidGlass(cornerRadius: 26)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        if value.translation.height > 80 {
                            dismissMadeleineDrawer()
                        }
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 22, bottomLeading: 0, bottomTrailing: 0, topTrailing: 22),
                style: .continuous
            )
            .fill(Color.black.opacity(0.92))
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func dismissMadeleineDrawer() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
            app.watchingWithMadeleine = false
        }
    }

    // MARK: - Helpers

    private var relatedVideos: [VideoItem] {
        app.videos.filter { $0.id != video?.id }
    }

    private var descriptionCopy: String {
        """
        \(video?.title ?? "This video") — filmed and edited for GojoGo Watch.

        In this episode we dig into craft, tools, and the messy middle of making things. Chapters in description. Sources linked by Madeleine if you ask.

        #gojogo #watch #longform
        """
    }

    private func actionChip(icon: String, title: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            chipLabel(icon: icon, title: title)
        }
        .buttonStyle(SoftPressStyle())
    }

    private func chipLabel(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
            if !title.isEmpty {
                Text(title).font(.system(size: 13, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }

    private func relatedRow(_ item: VideoItem) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                MediaImage(url: item.thumbURL, data: item.thumbData, cornerRadius: 10)
                    .frame(width: 148, height: 84)
                    .clipped()
                Text(item.duration)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.75)))
                    .padding(5)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(item.meta)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    var body: some View {
        if let chip = message.fileChip {
            HStack { FileChipView(chip: chip); Spacer() }
        } else if message.fromUser {
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 13, weight: .medium)).lineSpacing(2)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 18, bottomLeading: 18,
                                                                  bottomTrailing: 4, topTrailing: 18),
                                               style: .continuous)
                            .fill(Color.white))
            }
        } else {
            HStack {
                Text(message.text)
                    .font(.system(size: 13)).lineSpacing(2)
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 18, bottomLeading: 18,
                                                                  bottomTrailing: 18, topTrailing: 4),
                                               style: .continuous)
                            .fill(Color.white.opacity(0.08)))
                    .overlay(
                        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 18, bottomLeading: 18,
                                                                  bottomTrailing: 18, topTrailing: 4),
                                               style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                Spacer(minLength: 40)
            }
        }
    }
}
