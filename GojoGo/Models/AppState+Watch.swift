import SwiftUI
import UIKit

// MARK: - Live Watch wiring
//
// The long-form feed and Shorts used to be session-cache-only: a video existed
// on the device that uploaded it and nowhere else, and its "views" were that
// device's playbacks. Both feeds now come from the `watch` module, and every
// mutation the UI makes optimistically is mirrored to it.
//
// Anything still local — a clip whose upload is in flight, or one restored from
// a cache written before this — keeps working: each sync method is a no-op for
// an id the server has never seen.

extension AppState {

    // MARK: Reading

    /// Pull-to-refresh on Watch, and the initial load after connecting.
    func refreshWatch() async {
        guard backendConnected else {
            // Offline: nothing to sync against. Keep whatever the cache holds —
            // the user can still play those files from disk — and just repair
            // any refs that a rebuild invalidated.
            repairCachedMedia()
            return
        }
        async let videosPage = try? WatchStore.shared.fetchVideos()
        async let shortsPage = try? WatchStore.shared.fetchShorts()
        let (remoteVideos, remoteShorts) = await (videosPage, shortsPage)

        if let remoteVideos {
            withAnimation(.easeOut(duration: 0.25)) {
                videos = merge(remote: remoteVideos.videos, local: videos, id: \.id)
            }
            watchNextBefore = remoteVideos.nextBefore
        }
        if let remoteShorts {
            withAnimation(.easeOut(duration: 0.25)) {
                shorts = merge(remote: remoteShorts.shorts, local: shorts, id: \.id)
            }
            shortsNextBefore = remoteShorts.nextBefore
        }
        adoptSubscriberCounts()
        schedulePersist()
    }

    /// Server truth wins for anything the server knows about; a purely local
    /// item (upload still in flight) is kept and appended after it. The local
    /// copy's `imageData`/`thumbData` is carried over so a freshly published
    /// video doesn't flash an empty poster while its thumbnail downloads.
    private func merge<T>(remote: [T], local: [T], id: KeyPath<T, UUID>) -> [T] {
        let remoteIds = Set(remote.map { $0[keyPath: id] })
        let localOnly = local.filter {
            !remoteIds.contains($0[keyPath: id])
                && !WatchStore.shared.isLive($0[keyPath: id])
        }
        return localOnly + remote
    }

    /// Copies follower counts learned from any video's channel into the cache
    /// the "N subscribers" line reads.
    func adoptSubscriberCounts() {
        for (handle, count) in WatchStore.shared.subscriberCountByHandle {
            followerCountByHandle[handle] = count
        }
    }

    /// Next page of the long-form feed, triggered near the bottom.
    func loadMoreWatchIfNeeded(after videoID: UUID) {
        guard backendConnected,
              !watchLoadingMore,
              let cursor = watchNextBefore,
              let index = videos.firstIndex(where: { $0.id == videoID }),
              index >= videos.count - 4 else { return }
        watchLoadingMore = true
        Task {
            defer { watchLoadingMore = false }
            guard let page = try? await WatchStore.shared.fetchVideos(before: cursor) else { return }
            watchNextBefore = page.nextBefore
            let existing = Set(videos.map(\.id))
            videos.append(contentsOf: page.videos.filter { !existing.contains($0.id) })
            adoptSubscriberCounts()
        }
    }

    /// Next page of Shorts, triggered as the pager nears the end.
    func loadMoreShortsIfNeeded(currentIndex: Int) {
        guard backendConnected,
              !shortsLoadingMore,
              let cursor = shortsNextBefore,
              currentIndex >= shorts.count - 3 else { return }
        shortsLoadingMore = true
        Task {
            defer { shortsLoadingMore = false }
            guard let page = try? await WatchStore.shared.fetchShorts(before: cursor) else { return }
            shortsNextBefore = page.nextBefore
            let existing = Set(shorts.map(\.id))
            shorts.append(contentsOf: page.shorts.filter { !existing.contains($0.id) })
            adoptSubscriberCounts()
        }
    }

    /// Pulls a channel's uploads into the profile reels grid.
    func refreshChannelVideos(of profileID: UUID) async {
        guard backendConnected,
              let list = try? await WatchStore.shared.fetchChannelVideos(profileID) else { return }
        let existingVideos = Set(videos.map(\.id))
        let existingShorts = Set(shorts.map(\.id))
        for dto in list {
            if dto.kind == "SHORT" {
                guard !existingShorts.contains(dto.id) else { continue }
                shorts.append(WatchStore.shared.mapShort(dto))
            } else {
                guard !existingVideos.contains(dto.id) else { continue }
                videos.append(WatchStore.shared.mapVideo(dto))
            }
        }
        adoptSubscriberCounts()
        schedulePersist()
    }

    // MARK: Publishing

    /// Uploads the movie (and its cover) and swaps the optimistic local item
    /// for the server's. The local id is kept only until the server answers —
    /// after that every mutation addresses the real one.
    func syncPublishVideo(localID: UUID, kind: String, title: String?, description: String?,
                          thumbData: Data?, videoRef: String?, durationSeconds: Int?) {
        guard backendConnected else { return }
        Task {
            do {
                guard let videoUrl = try await uploadVideoFile(videoRef) else { return }
                let thumbUrl = try await uploadThumbnail(thumbData)
                let dto = try await WatchStore.shared.create(
                    kind: kind, title: title, description: description,
                    thumbUrl: thumbUrl, videoUrl: videoUrl, durationSeconds: durationSeconds)
                if kind == "SHORT" {
                    if let i = shorts.firstIndex(where: { $0.id == localID }) {
                        var merged = WatchStore.shared.mapShort(dto)
                        // Keep the local poster bytes so the card doesn't blink
                        // while the uploaded thumbnail is fetched back.
                        merged.imageData = shorts[i].imageData
                        merged.videoURL = shorts[i].videoURL ?? merged.videoURL
                        shorts[i] = merged
                    }
                } else if let i = videos.firstIndex(where: { $0.id == localID }) {
                    var merged = WatchStore.shared.mapVideo(dto)
                    merged.thumbData = videos[i].thumbData
                    merged.videoURL = videos[i].videoURL ?? merged.videoURL
                    videos[i] = merged
                }
                adoptSubscriberCounts()
                schedulePersist()
            } catch {
                #if DEBUG
                print("Video publish sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Reads a durable local movie ref off disk and PUTs it to S3. A ref that
    /// is already an https URL is passed straight through.
    private func uploadVideoFile(_ ref: String?) async throws -> String? {
        guard let ref, !ref.isEmpty else { return nil }
        if ref.hasPrefix("https://") || ref.hasPrefix("http://") { return ref }
        guard let resolved = VideoLibrary.resolve(ref),
              let fileURL = URL(string: resolved), fileURL.isFileURL,
              let data = try? Data(contentsOf: fileURL) else { return nil }
        let type = fileURL.pathExtension.lowercased() == "mov" ? "video/quicktime" : "video/mp4"
        return try await APIClient.shared.uploadMedia(data, contentType: type)
    }

    private func uploadThumbnail(_ data: Data?) async throws -> String? {
        guard let data else { return nil }
        let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) ?? data
        return try await APIClient.shared.uploadMedia(jpeg, contentType: "image/jpeg")
    }

    /// Pushes an edit made in the details sheet.
    func syncVideoDetails(_ id: UUID, title: String, details: String, thumbData: Data?) {
        guard WatchStore.shared.isLive(id) else { return }
        Task {
            do {
                let thumbUrl = try await uploadThumbnail(thumbData)
                let dto = try await WatchStore.shared.update(
                    id, title: title, description: details, thumbUrl: thumbUrl)
                if let i = videos.firstIndex(where: { $0.id == id }) {
                    var merged = WatchStore.shared.mapVideo(dto)
                    merged.thumbData = thumbData ?? videos[i].thumbData
                    merged.videoURL = videos[i].videoURL ?? merged.videoURL
                    videos[i] = merged
                }
                schedulePersist()
            } catch {
                #if DEBUG
                print("Video details sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: Engagement

    func syncVideoLike(_ id: UUID, liked: Bool) {
        guard WatchStore.shared.isLive(id) else { return }
        Task {
            do {
                if liked { try await WatchStore.shared.like(id) }
                else { try await WatchStore.shared.unlike(id) }
            } catch {
                #if DEBUG
                print("Video like sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func syncVideoSave(_ id: UUID, saved: Bool) {
        guard WatchStore.shared.isLive(id) else { return }
        Task {
            do {
                if saved { try await WatchStore.shared.save(id) }
                else { try await WatchStore.shared.unsave(id) }
            } catch {
                #if DEBUG
                print("Video save sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Server-side this is one row per (video, viewer), so a count is distinct
    /// viewers and a replay can't inflate it. The local bump stays optimistic.
    func syncVideoView(_ id: UUID) {
        guard WatchStore.shared.isLive(id) else { return }
        Task { try? await WatchStore.shared.recordView(id) }
    }

    func syncVideoDelete(_ id: UUID) {
        guard WatchStore.shared.isLive(id) else { return }
        Task {
            do {
                try await WatchStore.shared.delete(id)
            } catch {
                #if DEBUG
                print("Video delete sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: Comments

    func refreshVideoComments(for videoID: UUID) {
        Task {
            if let live = try? await WatchStore.shared.comments(for: videoID) {
                commentsByPost[videoID] = live.reversed()
                if let i = videos.firstIndex(where: { $0.id == videoID }) {
                    videos[i].commentCount = live.count
                }
            }
        }
    }

    func syncNewVideoComment(text: String, videoID: UUID, optimisticID: UUID) {
        guard WatchStore.shared.isLive(videoID) else { return }
        Task {
            do {
                let real = try await WatchStore.shared.addComment(text, to: videoID)
                if var list = commentsByPost[videoID],
                   let i = list.firstIndex(where: { $0.id == optimisticID }) {
                    list[i] = real
                    commentsByPost[videoID] = list
                }
            } catch {
                #if DEBUG
                print("Video comment sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func syncVideoCommentLike(commentID: UUID, liked: Bool) {
        Task {
            do {
                if liked { try await WatchStore.shared.likeComment(commentID) }
                else { try await WatchStore.shared.unlikeComment(commentID) }
            } catch {
                #if DEBUG
                print("Video comment like sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }
}
