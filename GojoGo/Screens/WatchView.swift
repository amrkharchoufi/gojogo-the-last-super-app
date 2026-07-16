import SwiftUI

struct LongFormFeedView: View {
    @EnvironmentObject var app: AppState
    @State private var hideChrome = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 18) {
                    ForEach(app.videos) { VideoCard(video: $0) }
                    Color.clear.frame(height: tabBarInset)
                }
                .padding(.top, 92)
            }
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
                    colors: [Color.black.opacity(0.92), Color.black.opacity(0)],
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
                        withAnimation(.easeOut(duration: 0.25)) { app.watchSubFeed = all[idx + 1] }
                    } else if v.translation.width > 0, idx > 0 {
                        withAnimation(.easeOut(duration: 0.25)) { app.watchSubFeed = all[idx - 1] }
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
        Button {
            app.playVideo(live.id)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    MediaImage(url: live.thumbURL, data: live.thumbData, cornerRadius: 0)
                        .frame(maxWidth: .infinity)
                        .frame(height: thumbHeight)
                        .clipped()
                        .background(Color.white.opacity(0.06))

                    Text(live.duration)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.black.opacity(0.82)))
                        .padding(8)
                }

                HStack(alignment: .top, spacing: 12) {
                    UserAvatar(
                        size: 36,
                        letter: String(live.channel.prefix(1)).uppercased(),
                        imageURL: live.thumbURL
                    )
                    .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(live.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(live.meta)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .frame(width: 28, height: 28)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
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
            Button {
                app.playVideo(live.id)
            } label: {
                Label("Play", systemImage: "play.fill")
            }
        }
    }
}

func formatCount(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
    return "\(n)"
}
