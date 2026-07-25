import SwiftUI
import UIKit

/// Stories on the live backend: composing (photo / video / text card, with
/// overlays), the engagement loop (reactions, replies, viewers, mute), and what
/// outlives the 24 hours (archive, highlights, close friends).
///
/// Same contract as the other verticals — optimistic UI first, the API call
/// behind it, and a revert that explains itself when the call fails. Anything
/// that isn't server-backed (SampleData rings, an offline session) keeps working
/// locally instead of going dead.
@MainActor
extension AppState {

    // MARK: - Notices

    func showStoryNotice(_ text: String, duration: TimeInterval = 3.5) {
        storyNoticeTask?.cancel()
        withAnimation(.ggSnappy) { storyNotice = text }
        storyNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.ggSnappy) { self?.storyNotice = nil }
        }
    }

    func dismissStoryNotice() {
        storyNoticeTask?.cancel()
        withAnimation(.ggSnappy) { storyNotice = nil }
    }

    // MARK: - Composing

    /// Posts one or more frames: they appear in your ring immediately, then the
    /// upload swaps each local frame for its server-backed twin.
    func postStory(_ drafts: [DraftStoryFrame]) {
        let renderable = drafts.filter { draft in
            switch draft.kind {
            case .text: return draft.caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            case .video: return draft.videoFileURL != nil
            case .image: return draft.imageData != nil
            }
        }
        guard !renderable.isEmpty else { return }

        let local = renderable.map { draft in
            StoryFrame(
                kind: draft.kind,
                imageData: draft.imageData,
                localVideoURL: draft.videoFileURL,
                durationMs: draft.durationMs,
                caption: draft.caption,
                background: draft.background,
                overlays: draft.overlays,
                audience: draft.audience,
                music: draft.music,
                seen: true,           // your own story is never "unseen" to you
                createdAt: Date(),
                expiresAt: Date().addingTimeInterval(24 * 3600))
        }
        insertIntoOwnRing(local)

        if backendConnected {
            let ids = local.map(\.id)
            Task { await uploadStory(renderable, localFrameIDs: ids) }
        }
        schedulePersist()
    }

    private func insertIntoOwnRing(_ frames: [StoryFrame]) {
        if let i = stories.firstIndex(where: \.isYou) {
            stories[i].frames.append(contentsOf: frames)
        } else {
            stories.insert(
                Story(name: "You",
                      letter: String((user.name.first ?? "g").uppercased()),
                      gradient: user.avatarGradient,
                      frames: frames,
                      isYou: true,
                      avatarURL: user.avatarURL),
                at: 0)
        }
    }

    private func uploadStory(_ drafts: [DraftStoryFrame], localFrameIDs: [UUID]) async {
        do {
            var bodies: [CreateStoryFrameBody] = []
            for draft in drafts {
                bodies.append(try await upload(draft))
            }
            let created = try await StoriesStore.shared.create(bodies)
            reconcileOwnRing(localFrameIDs: localFrameIDs, with: created)
            schedulePersist()
        } catch {
            // The frames stay on screen but never became real — say so rather
            // than leaving a story that silently doesn't exist for anyone else.
            removeFromOwnRing(localFrameIDs)
            showStoryNotice("Couldn't post your story. Check your connection and try again.")
            #if DEBUG
            print("Story upload failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Uploads a draft's media (and any sticker artwork) and returns the body.
    private func upload(_ draft: DraftStoryFrame) async throws -> CreateStoryFrameBody {
        var imageUrl: String?
        var videoUrl: String?

        if let data = draft.imageData {
            imageUrl = try await uploadStoryImage(data)
        }
        if let file = draft.videoFileURL {
            let data = try Data(contentsOf: file)
            let type = file.pathExtension.lowercased() == "mov" ? "video/quicktime" : "video/mp4"
            videoUrl = try await APIClient.shared.uploadMedia(data, contentType: type)
        }

        // Stickers are rendered from their URL at view time, so each one has to
        // exist on S3 before the frame can reference it.
        var overlays = draft.overlays
        for index in overlays.indices where overlays[index].imageURL == nil {
            if let data = overlays[index].imageData {
                overlays[index].imageURL = try await APIClient.shared
                    .uploadMedia(data, contentType: "image/png")
            }
        }

        return CreateStoryFrameBody(
            mediaType: draft.kind.rawValue,
            imageUrl: imageUrl,
            videoUrl: videoUrl,
            durationMs: draft.durationMs,
            caption: draft.caption,
            overlays: overlays.storyJSON,
            background: draft.kind == .text ? draft.background.token : nil,
            audience: draft.audience.rawValue,
            musicTrackId: draft.music?.trackID,
            musicStartMs: draft.music?.startMs,
            musicDurationMs: draft.music?.durationMs)
    }

    private func uploadStoryImage(_ data: Data) async throws -> String {
        let type = APIClient.imageContentType(for: data)
        if type == "image/jpeg" || type == "image/png" || type == "image/gif" {
            return try await APIClient.shared.uploadMedia(data, contentType: type)
        }
        let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) ?? data
        return try await APIClient.shared.uploadMedia(jpeg, contentType: "image/jpeg")
    }

    /// Swaps each optimistic frame for the server's, keeping the local media so
    /// the ring doesn't flicker back through a network fetch it already has.
    private func reconcileOwnRing(localFrameIDs: [UUID], with created: [StoryFrameDTO]) {
        guard let ring = stories.firstIndex(where: \.isYou) else { return }
        for (localID, dto) in zip(localFrameIDs, created) {
            guard let i = stories[ring].frames.firstIndex(where: { $0.id == localID }) else { continue }
            let local = stories[ring].frames[i]
            var server = StoriesStore.shared.map(dto)
            server.imageData = local.imageData
            server.localVideoURL = local.localVideoURL
            server.seen = true
            stories[ring].frames[i] = server
        }
        if viewingStory?.isYou == true {
            viewingStory = stories[ring]
        }
    }

    private func removeFromOwnRing(_ frameIDs: [UUID]) {
        guard let ring = stories.firstIndex(where: \.isYou) else { return }
        stories[ring].frames.removeAll { frameIDs.contains($0.id) }
        if viewingStory?.isYou == true {
            if stories[ring].frames.isEmpty {
                closeStoryViewer()
            } else {
                viewingStory = stories[ring]
                viewingFrameIndex = min(viewingFrameIndex, stories[ring].frames.count - 1)
            }
        }
    }

    // MARK: - Deleting

    func deleteStoryFrame(storyID: UUID, frameID: UUID) {
        guard let si = stories.firstIndex(where: { $0.id == storyID }), stories[si].isYou else { return }
        let removed = stories[si].frames.first(where: { $0.id == frameID })
        stories[si].frames.removeAll { $0.id == frameID }

        let emptied = stories[si].frames.isEmpty
        if viewingStory?.id == storyID {
            if emptied {
                closeStoryViewer()
            } else {
                viewingStory = stories[si]
                viewingFrameIndex = min(viewingFrameIndex, stories[si].frames.count - 1)
            }
        }

        guard StoriesStore.shared.isLive(frameID) else {
            schedulePersist()
            return
        }
        Task {
            do {
                try await StoriesStore.shared.delete(frameID)
            } catch {
                // Put it back — a story that reappears is honest; one that looks
                // deleted while everyone else still sees it is not.
                if let restored = removed, let si = stories.firstIndex(where: { $0.id == storyID }) {
                    stories[si].frames.append(restored)
                    stories[si].frames.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
                }
                showStoryNotice("Couldn't delete that story.")
            }
            schedulePersist()
        }
    }

    // MARK: - Reactions

    /// Tapping the emoji you already left clears it, like Instagram.
    func reactToStoryFrame(storyID: UUID, frameID: UUID, emoji: String) {
        guard let si = stories.firstIndex(where: { $0.id == storyID }),
              let fi = stories[si].frames.firstIndex(where: { $0.id == frameID }) else { return }
        let previous = stories[si].frames[fi].myReaction
        let next: String? = previous == emoji ? nil : emoji
        stories[si].frames[fi].myReaction = next
        if viewingStory?.id == storyID {
            viewingStory = stories[si]
        }
        markFrameSeen(storyID: storyID, frameID: frameID)

        guard StoriesStore.shared.isLive(frameID) else { return }
        Task {
            do {
                if let next {
                    try await StoriesStore.shared.react(frameID, emoji: next)
                } else {
                    try await StoriesStore.shared.unreact(frameID)
                }
            } catch {
                if let si = stories.firstIndex(where: { $0.id == storyID }),
                   let fi = stories[si].frames.firstIndex(where: { $0.id == frameID }) {
                    stories[si].frames[fi].myReaction = previous
                    if viewingStory?.id == storyID { viewingStory = stories[si] }
                }
                showStoryNotice("Couldn't send that reaction.")
            }
        }
    }

    // MARK: - Replies

    /// Replies are private between you and the story's author.
    @discardableResult
    func replyToStoryFrame(frameID: UUID, text: String) async -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, StoriesStore.shared.isLive(frameID) else { return false }
        do {
            let reply = try await StoriesStore.shared.reply(frameID, text: cleaned)
            storyReplies.append(reply)
            return true
        } catch {
            showStoryNotice("Couldn't send your reply.")
            return false
        }
    }

    /// Loads whatever the current frame can show: the author gets viewers and
    /// every reply, a viewer gets only the replies they sent.
    func loadInsightsForCurrentFrame() {
        storyReplies = []
        storyViewers = []
        guard let story = viewingStory,
              story.frames.indices.contains(viewingFrameIndex) else { return }
        let frame = story.frames[viewingFrameIndex]
        guard StoriesStore.shared.isLive(frame.id) else { return }

        let isMine = story.isYou
        storyInsightsLoading = true
        Task {
            async let replies = try? StoriesStore.shared.replies(frame.id)
            async let viewers = isMine ? try? StoriesStore.shared.viewers(frame.id) : nil
            let (loadedReplies, loadedViewers) = await (replies, viewers)
            // The user may have swiped on while these were in flight.
            guard viewingStory?.id == story.id,
                  viewingStory?.frames.indices.contains(viewingFrameIndex) == true,
                  viewingStory?.frames[viewingFrameIndex].id == frame.id else { return }
            storyReplies = loadedReplies ?? []
            storyViewers = loadedViewers ?? []
            storyInsightsLoading = false
        }
    }

    // MARK: - Mute

    func toggleStoryMute(authorID: UUID) {
        guard let si = stories.firstIndex(where: { $0.id == authorID }), !stories[si].isYou else { return }
        let muted = !stories[si].muted
        stories[si].muted = muted
        if viewingStory?.id == authorID { viewingStory = stories[si] }
        showStoryNotice(muted ? "Muted \(stories[si].name)'s stories" : "Unmuted \(stories[si].name)'s stories")

        guard backendConnected else { return }
        Task {
            do {
                if muted {
                    try await StoriesStore.shared.mute(authorID)
                } else {
                    try await StoriesStore.shared.unmute(authorID)
                }
            } catch {
                if let si = stories.firstIndex(where: { $0.id == authorID }) {
                    stories[si].muted = !muted
                }
                showStoryNotice("Couldn't update that setting.")
            }
        }
    }

    /// Pull-to-refresh for the stories directory — re-fetches the rings on their
    /// own, without dragging the whole home feed along the way `refreshSocial`
    /// does (that one owns posts and rings together, and is what Home pulls).
    func refreshStoryRings() async {
        guard backendConnected else { return }
        do {
            var rings = try await StoriesStore.shared.fetchRings()
            if !rings.contains(where: \.isYou) {
                rings.insert(Story(name: "You", letter: String((user.name.first ?? "g").uppercased()),
                                   gradient: user.avatarGradient, frames: [], isYou: true), at: 0)
            }
            withAnimation(.easeOut(duration: 0.25)) { stories = rings }
        } catch {
            #if DEBUG
            print("Story rings refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Archive

    func refreshStoryArchive() async {
        guard backendConnected else { return }
        storyArchive = (try? await StoriesStore.shared.archive()) ?? []
    }

    // MARK: - Highlights

    func refreshHighlights(for profileID: UUID? = nil) async {
        guard backendConnected else { return }
        storyHighlights = (try? await StoriesStore.shared.highlights(of: profileID)) ?? []
    }

    /// Plays a highlight in the story viewer. Its frames aren't part of the live
    /// rings, so the ring is held separately for the viewer to read.
    func openHighlight(_ highlight: StoryHighlight) {
        Task {
            guard let loaded = try? await StoriesStore.shared.highlightFrames(highlight.id),
                  !loaded.frames.isEmpty else {
                showStoryNotice("That highlight is empty.")
                return
            }
            let ring = Story(
                id: highlight.id,
                name: loaded.title,
                letter: String((loaded.title.first ?? "•").uppercased()),
                gradient: SocialStore.gradient(for: loaded.title),
                frames: loaded.frames,
                isYou: highlight.ownerID == SocialStore.shared.myProfileId,
                avatarURL: highlight.coverURL)
            playingHighlightRing = ring
            viewingHighlightTitle = loaded.title
            storyViewerRail = []
            viewingFrameIndex = 0
            viewingStory = ring
            storyOverlayActive = true
        }
    }

    @discardableResult
    func saveHighlight(id: UUID?, title: String, coverURL: String?, frameIDs: [UUID]) async -> Bool {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, backendConnected else { return false }
        do {
            _ = try await StoriesStore.shared.saveHighlight(
                id: id, title: cleaned, coverURL: coverURL, frameIDs: frameIDs)
            await refreshHighlights()
            return true
        } catch {
            showStoryNotice("Couldn't save that highlight.")
            return false
        }
    }

    func deleteHighlight(_ id: UUID) {
        let previous = storyHighlights
        storyHighlights.removeAll { $0.id == id }
        Task {
            do {
                try await StoriesStore.shared.deleteHighlight(id)
            } catch {
                storyHighlights = previous
                showStoryNotice("Couldn't delete that highlight.")
            }
        }
    }

    // MARK: - Close friends

    func refreshCloseFriends() async {
        guard backendConnected else { return }
        closeFriends = (try? await StoriesStore.shared.closeFriends()) ?? []
    }

    func saveCloseFriends(_ ids: [UUID]) async {
        guard backendConnected else { return }
        let previous = closeFriends
        do {
            closeFriends = try await StoriesStore.shared.setCloseFriends(ids)
        } catch {
            closeFriends = previous
            showStoryNotice("Couldn't update your close friends list.")
        }
    }
}
