import SwiftUI

struct CommentsSheet: View {
    @EnvironmentObject var app: AppState
    @FocusState private var focused: Bool
    @StateObject private var autocomplete = MentionAutocomplete()
    /// When true, renders as an in-view panel (no sheet detents). Used under
    /// the long-form player so comments don't fight the `fullScreenCover`.
    var embedded: Bool = false

    /// How many replies a thread shows before it asks to be opened.
    ///
    /// Zero, so "View N replies" sits directly under the comment it belongs to.
    /// Showing a couple first put the control below the last preview, where it
    /// reads as belonging to *that* reply rather than to the thread — and a
    /// thread with three replies showed two of them and then offered to reveal
    /// "1 reply", which is the confusing half-state.
    private static let replyPreviewCount = 0

    private var postID: UUID? { app.commentingPostID }
    private var comments: [Comment] {
        guard let id = postID else { return [] }
        return app.commentsByPost[id] ?? []
    }

    /// The watch module has no reply table of its own, so a video thread stays
    /// flat rather than offering an affordance that would post a stray comment.
    private var canReply: Bool {
        guard let id = postID else { return false }
        return !app.isVideoThread(id)
    }

    var body: some View {
        Group {
            if embedded {
                panel
            } else {
                panel
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            autocomplete.localSource = { [weak app] in app?.mentionCandidates ?? [] }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true }
        }
        // Reporting opens from a comment's context menu here. This sheet is
        // itself a sheet, so the root's copy can't present over it and stands
        // down whenever a thread is open — including the embedded case inside
        // the long-form player, which is why this is unconditional.
        .safetyPresentations(active: true)
    }

    private var panel: some View {
        NavigationStack {
            ZStack {
                GGColor.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(comments) { c in
                                thread(c)
                            }
                        }
                        .padding(20)
                    }

                    Divider().overlay(GGColor.ink(0.08))

                    composer
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { app.closeComments() }
                        .fontWeight(.semibold)
                        .foregroundStyle(GGColor.textPrimary)
                }
            }
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 0) {
            MentionSuggestionBar(autocomplete: autocomplete) { candidate in
                app.draftComment = autocomplete.complete(app.draftComment, with: candidate)
            }
            // Scoped to the bar rather than run as a `withAnimation` around the
            // state change: a global transaction also caught the reply banner
            // below, which is inserted in the same frame (tapping Reply seeds
            // the draft with "@handle"). The banner's text then animated from
            // the composer's old position — it appeared under the text field
            // and slid up into place.
            .animation(.easeOut(duration: 0.15), value: autocomplete.candidates.count)

            if let handle = app.replyingToHandle {
                HStack(spacing: 8) {
                    Text("Replying to @\(handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(GGColor.textSecondary)
                    Spacer(minLength: 0)
                    Button {
                        app.cancelReply()
                        app.draftComment = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(GGColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(GGColor.ink(0.04))
            }

            HStack(spacing: 10) {
                UserAvatar(size: 32, letter: String(app.user.name.prefix(1)),
                           imageURL: app.user.avatarURL)
                TextField(app.replyingToHandle == nil ? "Add a comment…" : "Add a reply…",
                          text: $app.draftComment, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(1...4)
                    .focused($focused)
                    .autocorrectionDisabled(autocomplete.token != nil)
                    .textInputAutocapitalization(autocomplete.token != nil ? .never : .sentences)
                Button {
                    autocomplete.reset()
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
        // The banner and the field it sits above have to move as one piece.
        // Silencing the banner alone (a `.transaction { $0.animation = nil }` on
        // it) was the previous fix and it is what brought the artefact back: the
        // row snapped to its final place while the text field below still slid
        // down under whatever transaction was in flight — the keyboard rising,
        // a poll republishing AppState — so for those few frames the banner sat
        // *under* the field and then the field cleared off it. Suppressing the
        // animation for the whole composer, keyed to the one state change that
        // inserts the row, means both are simply there together.
        .animation(nil, value: app.replyingToHandle)
        .onChange(of: app.draftComment) { _, text in
            autocomplete.update(for: text, connected: app.backendConnected)
        }
    }

    private var canSend: Bool {
        !app.draftComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Thread

    @ViewBuilder
    private func thread(_ root: Comment) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            commentRow(root)

            if !root.replies.isEmpty || root.replyCount > 0 {
                let expanded = app.expandedCommentIDs.contains(root.id)
                let shown = expanded ? root.replies
                    : Array(root.replies.prefix(Self.replyPreviewCount))

                ForEach(shown) { reply in
                    commentRow(reply)
                        .padding(.leading, 44)
                }

                if let label = expandLabel(root, expanded: expanded) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            app.toggleRepliesExpanded(root.id)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(GGColor.ink(0.18))
                                .frame(width: 20, height: 1)
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(GGColor.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 44)
                }
            }
        }
    }

    /// nil when there is nothing left to reveal — a two-reply thread showing
    /// both of them needs no control.
    private func expandLabel(_ root: Comment, expanded: Bool) -> String? {
        let total = max(root.replyCount, root.replies.count)
        if expanded {
            return total > Self.replyPreviewCount ? "Hide replies" : nil
        }
        let hidden = total - min(root.replies.count, Self.replyPreviewCount)
        guard hidden > 0 else { return nil }
        return hidden == 1 ? "View 1 reply" : "View \(hidden) replies"
    }

    private func commentRow(_ c: Comment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            UserAvatar(size: c.parentID == nil ? 36 : 28,
                       letter: String(c.author.prefix(1)).uppercased(),
                       imageURL: c.avatarURL)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        app.openUserProfile(handle: c.author, avatarURL: c.avatarURL)
                    } label: {
                        Text(c.author).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                    }
                    .buttonStyle(.plain)
                    Text(c.timeAgo).font(.system(size: 12))
                        .foregroundStyle(GGColor.textTertiary)
                }

                MentionedText(text: c.text, mentions: c.mentions,
                              font: .system(size: 14),
                              color: GGColor.textPrimary.opacity(0.9)) { handle, profileID in
                    app.openTaggedProfile(handle: handle, profileID: profileID)
                }
                .fixedSize(horizontal: false, vertical: true)

                if let id = postID {
                    HStack(spacing: 16) {
                        Button {
                            app.toggleCommentLike(postID: id, commentID: c.id)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: c.liked ? "heart.fill" : "heart")
                                if c.likeCount > 0 { Text("\(c.likeCount)") }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(c.liked ? GGColor.white : GGColor.textTertiary)
                        }
                        .buttonStyle(.plain)

                        if canReply {
                            Button {
                                app.beginReply(to: c)
                                focused = true
                            } label: {
                                Text("Reply")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(GGColor.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        // Long-press rather than a visible control: a report button next to
        // every comment is a report button people press to see what it does.
        // Only on other people's — your own has delete, one level up.
        .contextMenu {
            if !isMine(c), canReply {
                Button(role: .destructive) {
                    app.openReport(.comment, id: c.id, label: "@\(c.author)'s comment")
                } label: {
                    Label("Report comment", systemImage: "flag")
                }
            }
        }
    }

    private func isMine(_ c: Comment) -> Bool {
        c.author.caseInsensitiveCompare(app.user.handle) == .orderedSame
    }
}
