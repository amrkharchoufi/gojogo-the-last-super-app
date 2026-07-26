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
        // Clips authored while the watch API was down (or before it shipped)
        // sit in the session cache forever unless we retry. Only `gojovideo:`
        // refs — never sample/bundle URLs.
        flushPendingVideoPublishes()
        schedulePersist()
    }

    /// Re-attempts S3 + `POST /v1/videos` for any on-device clip the server has
    /// never seen. Safe to call repeatedly: in-flight ids and live ids are skipped.
    func flushPendingVideoPublishes() {
        guard backendConnected else { return }
        for short in shorts {
            guard !WatchStore.shared.isLive(short.id),
                  let ref = short.videoURL,
                  ref.hasPrefix(VideoLibrary.prefix) else { continue }
            syncPublishVideo(localID: short.id, kind: "SHORT",
                             title: short.caption.isEmpty ? nil : short.caption,
                             description: nil,
                             thumbData: short.imageData, videoRef: ref,
                             durationSeconds: nil)
        }
        for video in videos {
            guard !WatchStore.shared.isLive(video.id),
                  let ref = video.videoURL,
                  ref.hasPrefix(VideoLibrary.prefix) else { continue }
            syncPublishVideo(localID: video.id, kind: "LONG_FORM",
                             title: video.title, description: video.details,
                             thumbData: video.thumbData, videoRef: ref,
                             durationSeconds: Self.durationSeconds(video.duration))
        }
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
    /// for the server's. Progress is written onto the local row so the publisher
    /// sees "Uploading…" — not a false "already live" state — until create returns.
    func syncPublishVideo(localID: UUID, kind: String, title: String?, description: String?,
                          thumbData: Data?, videoRef: String?, durationSeconds: Int?) {
        guard backendConnected else {
            setVideoPublishState(localID, kind: kind,
                                 .failed(message: "Sign in to publish"))
            return
        }
        guard videoPublishInFlight.insert(localID).inserted else { return }
        Task {
            defer { videoPublishInFlight.remove(localID) }
            setVideoPublishState(localID, kind: kind, .uploading(progress: 0))
            do {
                guard let videoUrl = try await uploadVideoFile(videoRef, localID: localID, kind: kind) else {
                    setVideoPublishState(localID, kind: kind,
                                         .failed(message: "Could not read the video file"))
                    return
                }
                setVideoPublishState(localID, kind: kind, .uploading(progress: 0.92))
                let thumbUrl = try await uploadThumbnail(thumbData)
                setVideoPublishState(localID, kind: kind, .uploading(progress: 0.97))
                let dto = try await WatchStore.shared.create(
                    kind: kind, title: title, description: description,
                    thumbUrl: thumbUrl, videoUrl: videoUrl, durationSeconds: durationSeconds)
                if kind == "SHORT" {
                    if let i = shorts.firstIndex(where: { $0.id == localID }) {
                        var merged = WatchStore.shared.mapShort(dto)
                        merged.imageData = shorts[i].imageData
                        merged.videoURL = shorts[i].videoURL ?? merged.videoURL
                        merged.publishState = .published
                        shorts[i] = merged
                    }
                } else if let i = videos.firstIndex(where: { $0.id == localID }) {
                    var merged = WatchStore.shared.mapVideo(dto)
                    merged.thumbData = videos[i].thumbData
                    merged.videoURL = videos[i].videoURL ?? merged.videoURL
                    merged.publishState = .published
                    videos[i] = merged
                }
                adoptSubscriberCounts()
                schedulePersist()
            } catch {
                setVideoPublishState(localID, kind: kind,
                                     .failed(message: error.localizedDescription))
                #if DEBUG
                print("Video publish sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Re-runs S3 + create for a local clip that failed (or never left the device).
    func retryPublishVideo(_ id: UUID) {
        if let short = shorts.first(where: { $0.id == id }) {
            guard short.publishState.isPending || !WatchStore.shared.isLive(id) else { return }
            syncPublishVideo(localID: short.id, kind: "SHORT",
                             title: short.caption.isEmpty ? nil : short.caption,
                             description: nil,
                             thumbData: short.imageData, videoRef: short.videoURL,
                             durationSeconds: nil)
            return
        }
        guard let video = videos.first(where: { $0.id == id }) else { return }
        guard video.publishState.isPending || !WatchStore.shared.isLive(id) else { return }
        syncPublishVideo(localID: video.id, kind: "LONG_FORM",
                         title: video.title, description: video.details,
                         thumbData: video.thumbData, videoRef: video.videoURL,
                         durationSeconds: Self.durationSeconds(video.duration))
    }

    private func setVideoPublishState(_ id: UUID, kind: String, _ state: VideoPublishState) {
        if kind == "SHORT" {
            if let i = shorts.firstIndex(where: { $0.id == id }) {
                shorts[i].publishState = state
            }
        } else if let i = videos.firstIndex(where: { $0.id == id }) {
            videos[i].publishState = state
        }
    }

    /// Reads a durable local movie ref off disk and PUTs it to S3. A ref that
    /// is already an https URL is passed straight through.
    private func uploadVideoFile(_ ref: String?, localID: UUID, kind: String) async throws -> String? {
        guard let ref, !ref.isEmpty else { return nil }
        if ref.hasPrefix("https://") || ref.hasPrefix("http://") { return ref }
        guard let resolved = VideoLibrary.resolve(ref) else { return nil }
        let fileURL: URL
        if let parsed = URL(string: resolved), parsed.isFileURL {
            fileURL = parsed
        } else if resolved.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: resolved)
        } else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        let type = fileURL.pathExtension.lowercased() == "mov" ? "video/quicktime" : "video/mp4"
        return try await APIClient.shared.uploadMedia(data, contentType: type) { [weak self] progress in
            Task { @MainActor in
                self?.setVideoPublishState(localID, kind: kind,
                                           .uploading(progress: min(0.9, progress * 0.9)))
            }
        }
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
