import SwiftUI

// MARK: - What a frame is

enum StoryMediaKind: String, Codable, Equatable {
    case image = "IMAGE"
    case video = "VIDEO"
    /// A caption on a plain card — no uploaded media.
    case text = "TEXT"

    init(wire: String?) {
        self = StoryMediaKind(rawValue: (wire ?? "").uppercased()) ?? .image
    }
}

enum StoryAudience: String, Codable, Equatable {
    case everyone = "ALL"
    case closeFriends = "CLOSE_FRIENDS"

    init(wire: String?) {
        self = StoryAudience(rawValue: (wire ?? "").uppercased()) ?? .everyone
    }

    var label: String {
        switch self {
        case .everyone: "Everyone"
        case .closeFriends: "Close friends"
        }
    }

    var icon: String {
        switch self {
        case .everyone: "globe"
        case .closeFriends: "person.2.fill"
        }
    }
}

// MARK: - Text-card backgrounds

/// Backgrounds for text stories. The app's palette is monochrome by design
/// (see `GGColor`), so these are tonal rather than colorful — a text story
/// still has to look like it belongs in the same app as everything else.
enum StoryBackground: String, CaseIterable, Codable {
    case ink, graphite, slate, bone, mist, night

    static func named(_ token: String?) -> StoryBackground {
        StoryBackground(rawValue: token ?? "") ?? .ink
    }

    var token: String { rawValue }

    /// Both stops are literal (not theme-adaptive): a story renders identically
    /// for the person who posted it and everyone who watches it.
    var gradient: LinearGradient {
        let stops: [String] = switch self {
        case .ink:      ["1C1C1E", "000000"]
        case .graphite: ["3A3A3C", "1C1C1E"]
        case .slate:    ["545458", "2C2C2E"]
        case .bone:     ["F2F2F7", "C7C7CC"]
        case .mist:     ["8E8E93", "48484A"]
        case .night:    ["000000", "2C2C2E"]
        }
        return LinearGradient(colors: stops.map { Color(hex: $0) },
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Text on a light card has to flip, or it disappears.
    var foreground: Color {
        self == .bone ? Color(hex: "111114") : .white
    }
}

// MARK: - Overlays

/// A text or sticker placed on a frame.
///
/// Positions are normalized (0…1 of the canvas) and font size is a fraction of
/// the canvas width, so a frame composed on any device renders identically on
/// every other one. Rendered live at view time rather than burned into the
/// image — a video frame couldn't be flattened without re-encoding it, and one
/// code path for all three kinds beats two.
struct StoryOverlay: Identifiable, Codable, Equatable {

    enum Kind: String, Codable {
        case text, sticker
    }

    var id: UUID
    var kind: Kind
    var text: String?
    /// Sticker artwork, uploaded on post. Local `imageData` is the pre-upload copy.
    var imageURL: String?
    var imageData: Data?
    var x: Double
    var y: Double
    var scale: Double
    var rotation: Double
    /// Fraction of the canvas width, so type scales with the screen.
    var fontScale: Double
    var isLight: Bool

    init(id: UUID = UUID(), kind: Kind, text: String? = nil,
         imageURL: String? = nil, imageData: Data? = nil,
         x: Double = 0.5, y: Double = 0.45, scale: Double = 1,
         rotation: Double = 0, fontScale: Double = 0.085, isLight: Bool = true) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageURL = imageURL
        self.imageData = imageData
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
        self.fontScale = fontScale
        self.isLight = isLight
    }

    /// `imageData` is deliberately dropped on the wire — it is the local copy of
    /// a sticker that has already been uploaded to `imageURL` by then.
    private enum CodingKeys: String, CodingKey {
        case id, kind, text, imageURL, x, y, scale, rotation, fontScale, isLight
    }
}

extension Array where Element == StoryOverlay {

    /// The `overlays` wire field: a JSON string the backend stores opaquely.
    var storyJSON: String? {
        guard !isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Anything unparseable is dropped rather than failing the whole frame —
    /// a story with no overlay still beats a story that won't render.
    static func fromStoryJSON(_ raw: String?) -> [StoryOverlay] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([StoryOverlay].self, from: data)) ?? []
    }
}

// MARK: - Music

/// A track from the shared catalog (`music` module).
struct MusicTrack: Identifiable, Equatable {
    let id: UUID
    var title: String
    var artist: String
    var artworkURL: String?
    var audioURL: String
    var durationMs: Int

    var durationLabel: String {
        let seconds = durationMs / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// The sound on a frame: which track, and which slice of it.
///
/// A copy of the catalog track rather than a pointer — a story keeps playing
/// the sound it was posted with even if the track is later pulled. The server
/// resolves every displayed field, so the client only ever sends the id and the
/// window.
struct StoryMusic: Equatable {
    var trackID: UUID
    var title: String
    var artist: String
    var artworkURL: String?
    var audioURL: String
    var startMs: Int
    var durationMs: Int

    /// Instagram caps a story's sound at 15s; the backend enforces the same.
    static let maxClipMs = 15_000

    var clipSeconds: Double { Double(durationMs) / 1000 }
    var startSeconds: Double { Double(startMs) / 1000 }
}

// MARK: - Engagement

/// A text reply to a frame. Private: the author reads every one, everyone else
/// reads only their own.
struct StoryReply: Identifiable, Equatable {
    let id: UUID
    var frameID: UUID
    var authorID: UUID
    var authorName: String
    var authorHandle: String?
    var authorAvatarURL: String?
    var text: String
    var timeAgo: String
    var mine: Bool
}

/// One row of the "Seen by" list.
struct StoryViewerInfo: Identifiable, Equatable {
    let id: UUID
    var name: String
    var handle: String?
    var avatarURL: String?
    var reaction: String?
    var timeAgo: String
}

// MARK: - Highlights

struct StoryHighlight: Identifiable, Equatable {
    let id: UUID
    var ownerID: UUID
    var title: String
    var coverURL: String?
    var frameCount: Int
}

struct CloseFriend: Identifiable, Equatable {
    let id: UUID
    var name: String
    var handle: String?
    var avatarURL: String?
}

// MARK: - Composing

/// One frame on its way to the server — local media that still needs uploading.
struct DraftStoryFrame: Identifiable, Equatable {
    let id = UUID()
    var kind: StoryMediaKind
    var imageData: Data?
    /// Local movie file for a video frame; its poster goes in `imageData`.
    var videoFileURL: URL?
    var durationMs: Int?
    var caption: String?
    var background: StoryBackground = .ink
    var overlays: [StoryOverlay] = []
    var audience: StoryAudience = .everyone
    /// Chosen track + clip window; the server re-resolves the metadata on post.
    var music: StoryMusic?
}

/// The quick reactions offered under someone else's story.
enum StoryReactions {
    static let quick = ["❤️", "🔥", "😂", "😮", "😢", "👏"]
}
