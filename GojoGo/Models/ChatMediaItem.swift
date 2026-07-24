import Foundation

/// One openable piece of media from a chat bubble — a photo, or a video with its
/// poster. Flattens the three shapes a message can take (single photo, single
/// video, carousel slide) into what the viewer, the share sheet and "save to
/// Photos" all need: some bytes or a URL, and whether it's a movie.
struct ChatMediaItem: Identifiable, Equatable {
    let id: UUID
    /// The message it came from, so a forward can re-send it.
    let messageID: UUID
    var imageData: Data?
    var imageURL: String?
    var isVideo: Bool
    var videoURL: String?
    var localVideoURL: URL?
    var durationLabel: String?

    init(id: UUID = UUID(), messageID: UUID, imageData: Data? = nil, imageURL: String? = nil,
         isVideo: Bool = false, videoURL: String? = nil, localVideoURL: URL? = nil,
         durationLabel: String? = nil) {
        self.id = id
        self.messageID = messageID
        self.imageData = imageData
        self.imageURL = imageURL
        self.isVideo = isVideo
        self.videoURL = videoURL
        self.localVideoURL = localVideoURL
        self.durationLabel = durationLabel
    }

    /// Playable movie: the on-device file when we still have it, else the CDN copy.
    var playableVideoURL: URL? {
        if let localVideoURL, FileManager.default.fileExists(atPath: localVideoURL.path) {
            return localVideoURL
        }
        return videoURL.flatMap(URL.init(string:))
    }

    /// A video whose file never made it (older messages carried only a poster).
    var isUnplayableVideo: Bool { isVideo && playableVideoURL == nil }

    var remoteImageURL: URL? {
        guard let imageURL, let url = URL(string: imageURL), url.scheme != nil else { return nil }
        return url
    }
}

extension WorldMessage {
    /// Everything openable in this message, in display order.
    var mediaItems: [ChatMediaItem] {
        switch kind {
        case .photo, .video:
            guard imageData != nil || imageURL != nil || videoURL != nil else { return [] }
            return [ChatMediaItem(messageID: id, imageData: imageData, imageURL: imageURL,
                                  isVideo: kind == .video, videoURL: videoURL,
                                  localVideoURL: localVideoURL, durationLabel: durationLabel)]
        case .carousel:
            return carouselItems.map {
                ChatMediaItem(messageID: id,
                              imageData: $0.imageData.isEmpty ? nil : $0.imageData,
                              imageURL: $0.imageURL, isVideo: $0.isVideo,
                              videoURL: $0.videoURL, localVideoURL: $0.localVideoURL,
                              durationLabel: $0.durationLabel)
            }
        default:
            return []
        }
    }
}

/// Where picked/captured movies live between staging and sending.
///
/// The photo picker hands over a temporary copy that iOS reclaims, so a video
/// staged in the composer has to be moved somewhere durable or it's gone by the
/// time the message is sent — which is why videos used to be poster-only.
enum ChatMediaOutbox {

    static var directory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("world-outbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes movie bytes into the outbox. Returns nil if it can't be stored.
    static func store(_ data: Data, extension ext: String = "mov") -> URL? {
        let url = directory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Copies a file the system owns (camera capture) into the outbox.
    static func adopt(_ source: URL) -> URL? {
        let url = directory.appendingPathComponent(
            "\(UUID().uuidString).\(source.pathExtension.isEmpty ? "mov" : source.pathExtension)")
        do {
            try FileManager.default.copyItem(at: source, to: url)
            return url
        } catch {
            return nil
        }
    }

    /// MIME type the backend's presign whitelist accepts for this file.
    static func contentType(for url: URL) -> String {
        url.pathExtension.lowercased() == "mp4" ? "video/mp4" : "video/quicktime"
    }
}
