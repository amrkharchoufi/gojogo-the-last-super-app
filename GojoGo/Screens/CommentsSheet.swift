import SwiftUI

struct CommentsSheet: View {
    @EnvironmentObject var app: AppState
    @FocusState private var focused: Bool

    private var postID: UUID? { app.commentingPostID }
    private var comments: [Comment] {
        guard let id = postID else { return [] }
        return app.commentsByPost[id] ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GGColor.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(comments) { c in
                                commentRow(c)
                            }
                        }
                        .padding(20)
                    }

                    Divider().overlay(GGColor.ink(0.08))

                    HStack(spacing: 10) {
                        UserAvatar(size: 32, letter: String(app.user.name.prefix(1)),
                                   imageURL: app.user.avatarURL)
                        TextField("Add a comment…", text: $app.draftComment, axis: .vertical)
                            .font(.system(size: 15))
                            .foregroundStyle(GGColor.textPrimary)
                            .lineLimit(1...4)
                            .focused($focused)
                        Button {
                            app.addComment()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(canSend ? GGColor.white : GGColor.ink(0.25))
                        }
                        .disabled(!canSend)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { app.closeComments() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true } }
    }

    private var canSend: Bool {
        !app.draftComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commentRow(_ c: Comment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            UserAvatar(size: 36, letter: String(c.author.prefix(1)).uppercased(),
                       imageURL: c.avatarURL)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(c.author).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(c.timeAgo).font(.system(size: 12))
                        .foregroundStyle(GGColor.textTertiary)
                }
                Text(c.text)
                    .font(.system(size: 14))
                    .foregroundStyle(GGColor.textPrimary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if let id = postID {
                    Button {
                        app.toggleCommentLike(postID: id, commentID: c.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: c.liked ? "heart.fill" : "heart")
                            if c.likeCount > 0 { Text("\(c.likeCount)") }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(c.liked ? Color.white : GGColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
