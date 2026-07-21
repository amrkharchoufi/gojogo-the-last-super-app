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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                app.playVideo(live.id)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    MediaImage(url: live.thumbURL, data: live.thumbData, cornerRadius: 0)
                        .frame(maxWidth: .infinity)
                        .frame(height: thumbHeight)
                        .clipped()
                        .background(GGColor.ink(0.06))

                    Text(live.duration)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.black.opacity(0.82)))
                        .padding(8)
                }
            }
            .buttonStyle(.plain)
            .contextMenu { menuItems }

            HStack(alignment: .top, spacing: 12) {
                Button {
                    app.openUserProfile(handle: live.channel, avatarURL: live.thumbURL)
                } label: {
                    UserAvatar(
                        size: 36,
                        letter: String(live.channel.prefix(1)).uppercased(),
                        imageURL: live.thumbURL
                    )
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)

                Button {
                    app.playVideo(live.id)
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
                            .foregroundStyle(GGColor.ink(0.55))
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

    @ViewBuilder
    private var menuItems: some View {
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
        Button(role: .destructive) {
            withAnimation(.ggTab) {
                app.reportVideo(live.id)
            }
        } label: {
            Label("Not interested", systemImage: "eye.slash")
        }
    }
}

func formatCount(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
    return "\(n)"
}
