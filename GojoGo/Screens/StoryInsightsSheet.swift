import SwiftUI

/// "Seen by" and the replies on one of your own frames.
///
/// Replies are private to you — every viewer's reply lands here and nowhere
/// else, which is why this sheet is the only place they're readable.
struct StoryInsightsSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let frameID: UUID?
    var repliesOnly: Bool = false

    @State private var tab: Tab = .viewers

    enum Tab: String, CaseIterable {
        case viewers = "Viewers"
        case replies = "Replies"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GGColor.sheetBG.ignoresSafeArea()

                VStack(spacing: 0) {
                    if !repliesOnly {
                        Picker("", selection: $tab) {
                            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }

                    if app.storyInsightsLoading && isEmpty {
                        Spacer()
                        ProgressView().tint(GGColor.textSecondary)
                        Spacer()
                    } else if isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
            }
            .navigationTitle(repliesOnly ? "Replies" : "Story insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(GGColor.accent)
                }
            }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if repliesOnly { tab = .replies }
            app.loadInsightsForCurrentFrame()
        }
    }

    private var showingReplies: Bool { repliesOnly || tab == .replies }

    private var isEmpty: Bool {
        showingReplies ? app.storyReplies.isEmpty : app.storyViewers.isEmpty
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: showingReplies ? "bubble.left" : "eye")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(GGColor.textTertiary)
            Text(showingReplies ? "No replies yet" : "No views yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(GGColor.textSecondary)
            Text(showingReplies
                 ? "Replies to your story are private — only you see them."
                 : "You'll see who watched this here.")
                .explanatory(13)
                .foregroundStyle(GGColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    @ViewBuilder
    private var list: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                if showingReplies {
                    ForEach(app.storyReplies) { reply in
                        replyRow(reply)
                        Divider().overlay(GGColor.hairline).padding(.leading, 62)
                    }
                } else {
                    ForEach(app.storyViewers) { viewer in
                        viewerRow(viewer)
                        Divider().overlay(GGColor.hairline).padding(.leading, 62)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func viewerRow(_ viewer: StoryViewerInfo) -> some View {
        HStack(spacing: 12) {
            UserAvatar(size: 38, letter: String(viewer.name.prefix(1)).uppercased(),
                       imageURL: viewer.avatarURL)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewer.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(GGColor.textPrimary)
                Text(viewer.timeAgo)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textTertiary)
            }

            Spacer()

            if let reaction = viewer.reaction {
                Text(reaction).font(.system(size: 20))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func replyRow(_ reply: StoryReply) -> some View {
        HStack(alignment: .top, spacing: 12) {
            UserAvatar(size: 38, letter: String(reply.authorName.prefix(1)).uppercased(),
                       imageURL: reply.authorAvatarURL)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(reply.mine ? "You" : reply.authorName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(reply.timeAgo)
                        .font(.system(size: 11))
                        .foregroundStyle(GGColor.textTertiary)
                }
                Text(reply.text)
                    .font(.system(size: 14))
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
