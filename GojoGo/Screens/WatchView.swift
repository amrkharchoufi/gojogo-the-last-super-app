import SwiftUI

struct LongFormFeedView: View {
    @EnvironmentObject var app: AppState
    @State private var hideChrome = false

    var body: some View {
        ZStack(alignment: .top) {
            GGColor.bg.ignoresSafeArea()

            // List (not ScrollView+LazyVStack) so the feed keeps its scroll position
            // when it re-renders on a bottom-nav tap — same fix as the Home feed.
            List {
                Group {
                    Color.clear.frame(height: 92)
                    if app.videos.isEmpty {
                        GGEmptyState(
                            icon: "play.rectangle",
                            title: "No videos yet",
                            message: "Long-form videos you watch and publish will show up here."
                        )
                        .padding(.top, 80)
                    } else {
                        ForEach(app.videos) { video in
                            VideoCard(video: video)
                                .padding(.bottom, 18)
                                .onAppear { app.loadMoreWatchIfNeeded(after: video.id) }
                        }
                    }
                    Color.clear.frame(height: tabBarInset)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .refreshable { await app.refreshWatch() }
            .trackScrollChrome(hidden: $hideChrome)

            HStack {
                Wordmark(size: 19)
                Spacer()
                WatchSegments(selection: $app.watchSubFeed)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .background(
                LinearGradient(
                    colors: [GGColor.bg.opacity(0.96), GGColor.bg.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 88)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            )
            .zIndex(20)
            .autoHideChrome(hideChrome)
        }
        .videoDeletionConfirmations(enabled: !app.showWatching && !app.showProfile)
    }
}

struct WatchView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            switch app.watchSubFeed {
            case .feed:   LongFormFeedView()
            case .shorts: ShortsView()
            case .tv:     GojoTVView()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 1.2 else { return }
                    guard abs(v.translation.width) > 60 else { return }
                    let all = WatchSubFeed.allCases
                    guard let idx = all.firstIndex(of: app.watchSubFeed) else { return }
                    if v.translation.width < 0, idx < all.count - 1 {
                        withAnimation(.ggTab) { app.watchSubFeed = all[idx + 1] }
                    } else if v.translation.width > 0, idx > 0 {
                        withAnimation(.ggTab) { app.watchSubFeed = all[idx - 1] }
                    }
                })
        // Keep others' feeds current while this tab is open — publish only lands
        // on their device after a refresh (no push yet).
        .task(id: app.backendConnected) {
            guard app.backendConnected else { return }
            await app.refreshWatch()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, app.backendConnected else { continue }
                await app.refreshWatch()
            }
        }
    }
}

/// YouTube-style long-form feed row.
struct VideoCard: View {
    @EnvironmentObject var app: AppState
    let video: VideoItem

    private var live: VideoItem {
        app.videos.first(where: { $0.id == video.id }) ?? video
    }

    private var thumbHeight: CGFloat {
        UIScreen.main.bounds.width * 9 / 16
    }

    /// The channel's own avatar. The thumbnail used to be passed here, which
    /// made every row's avatar a still from its own video.
    private var avatarURL: String? {
        app.authorAvatarURL(forChannel: live.channel, stored: live.authorAvatarURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if case .failed = live.publishState {
                    app.retryPublishVideo(live.id)
                } else {
                    app.playVideo(live.id)
                }
            } label: {
                ZStack(alignment: .bottom) {
                    MediaImage(url: live.thumbURL, data: live.thumbData, cornerRadius: 0)
                        .frame(maxWidth: .infinity)
                        .frame(height: thumbHeight)
                        .clipped()
                        .background(GGColor.ink(0.06))
                        .opacity(live.publishState.isPending ? 0.85 : 1)

                    if case .uploading(let progress) = live.publishState {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            publishBadge(text: live.meta, systemImage: "arrow.up.circle")
                                .padding(10)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Color.white.opacity(0.2))
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: max(4, geo.size.width * max(0, min(1, progress))))
                                }
                            }
                            .frame(height: 3)
                        }
                    } else if case .failed = live.publishState {
                        VStack {
                            Spacer(minLength: 0)
                            publishBadge(text: "Upload failed · Tap to retry",
                                         systemImage: "exclamationmark.triangle")
                                .padding(10)
                        }
                    } else {
                        Text(live.duration)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.black.opacity(0.82)))
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
            }
            .buttonStyle(.plain)
            .contextMenu { menuItems }

            HStack(alignment: .top, spacing: 12) {
                Button {
                    app.openUserProfile(handle: live.channel, avatarURL: avatarURL)
                } label: {
                    UserAvatar(
                        size: 36,
                        gradient: app.avatarGradient(forHandle: live.channel),
                        letter: String(live.channel.prefix(1)).uppercased(),
                        imageURL: avatarURL,
                        imageData: live.authorAvatarData
                    )
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)

                Button {
                    if case .failed = live.publishState {
                        app.retryPublishVideo(live.id)
                    } else {
                        app.playVideo(live.id)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(live.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(live.meta)
                            .font(.system(size: 13))
                            .foregroundStyle(live.publishState.isPending
                                             ? GGColor.textPrimary.opacity(0.7)
                                             : GGColor.ink(0.55))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    menuItems
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GGColor.ink(0.55))
                        .frame(width: 28, height: 28)
                        .padding(.top, 2)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)
        }
    }

    private func publishBadge(text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.72)))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var menuItems: some View {
        if case .failed = live.publishState {
            Button {
                app.retryPublishVideo(live.id)
            } label: {
                Label("Retry upload", systemImage: "arrow.clockwise")
            }
        }
        Button {
            app.playVideo(live.id)
        } label: {
            Label("Play", systemImage: "play.fill")
        }
        Button {
            app.toggleVideoLike(live.id)
        } label: {
            Label(live.liked ? "Unlike" : "Like",
                  systemImage: live.liked ? "hand.thumbsup.fill" : "hand.thumbsup")
        }
        Button {
            app.toggleVideoSave(live.id)
        } label: {
            Label(live.saved ? "Unsave" : "Save",
                  systemImage: live.saved ? "bookmark.fill" : "bookmark")
        }
        ShareLink(item: app.videoShareURL(for: live.id), subject: Text(live.title)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Divider()
        if app.canDeleteVideo(live.id) {
            Button {
                app.editVideoDetails(live.id)
            } label: {
                Label("Edit details", systemImage: "pencil")
            }
            Button(role: .destructive) {
                app.requestDeleteVideo(live.id)
            } label: {
                Label("Delete video", systemImage: "trash")
            }
        } else {
            Button(role: .destructive) {
                withAnimation(.ggTab) {
                    app.reportVideo(live.id)
                }
            } label: {
                Label("Not interested", systemImage: "eye.slash")
            }
        }
    }
}

func formatCount(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
    return "\(n)"
}
