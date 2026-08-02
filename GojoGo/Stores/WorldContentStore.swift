import Foundation

// MARK: - Wire DTOs

struct ContactDTO: Decodable {
    var contactId: UUID
    var displayName: String?
    var avatarUrl: String?
    var phone: String?
    var alias: String?
    var addedAt: String?
}

struct AddContactBody: Encodable {
    var phone: String
    var alias: String?
}

struct CircleDTO: Decodable {
    var id: UUID
    var name: String
    var colorHex: String?
    var memberIds: [UUID]?
    var createdAt: String?
}

struct SaveCircleBody: Encodable {
    var name: String
    var colorHex: String?
    var memberIds: [UUID]
}

struct WorldRichProfileDTO: Codable {
    var bio: String?
    var gender: String?
    var city: String?
    var languages: [String]?
    var education: String?
    var occupation: String?
    var interests: [String]?
    var favouriteBooks: [String]?
    var favouriteFilms: [String]?
    var favouriteTv: [String]?
    var favouriteSport: [String]?
    var favouriteGames: [String]?
}

struct WorldContactProfileDTO: Decodable {
    var profileId: UUID
    var displayName: String?
    var avatarUrl: String?
    var phone: String?
    var alias: String?
    var isContact: Bool
    var profile: WorldRichProfileDTO?
}

struct WorldContentDTO: Decodable {
    var id: UUID
    var authorId: UUID
    var authorName: String?
    var authorAvatarUrl: String?
    var kind: String
    var text: String?
    var mediaItems: [WorldMediaItemDTO]?
    var createdAt: String
    var expiresAt: String?
    var seen: Bool?
    /// Present only on your own content — a reader is never told which of the
    /// author's circles they landed in.
    var audience: String?
    var circleIds: [UUID]?
}

struct WorldStoryGroupDTO: Decodable {
    var authorId: UUID
    var authorName: String?
    var authorAvatarUrl: String?
    var allSeen: Bool
    var frames: [WorldContentDTO]
}

struct WorldFeedDTO: Decodable {
    var stories: [WorldStoryGroupDTO]
    var posts: [WorldContentDTO]
}

struct PublishContentBody: Encodable {
    var kind: String
    var text: String?
    var mediaItems: [WorldMediaItemDTO]?
    var audience: String
    var circleIds: [UUID]?
}

// MARK: - App models

/// One piece of GojoMessages content as the feed renders it.
struct WorldPost: Identifiable, Equatable {
    let id: UUID
    var authorID: UUID
    /// The name the server gave. `AppState` applies the viewer's private rename
    /// over the top, keyed by `authorID` — the wire never carries an alias.
    var authorName: String
    var authorAvatarURL: String?
    var kind: String
    var text: String
    var imageURLs: [String]
    var createdAt: Date
    var expiresAt: Date?
    var seen: Bool
    /// Only ever set on your own posts.
    var audience: WorldPostAudience?
    var circleIDs: [UUID]

    var isStory: Bool { kind == "story" }
    var isCarousel: Bool { imageURLs.count > 1 }
}

/// Who can read a post. There is no public case, and that absence is the point:
/// a GojoMessages post is seen by contacts or by chosen circles and by nobody
/// else, ever (ARCHITECTURE §2b decision 4).
enum WorldPostAudience: String, CaseIterable, Identifiable {
    case contacts = "CONTACTS"
    case circles = "CIRCLES"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .contacts: return "All my contacts"
        case .circles: return "Chosen circles"
        }
    }

    var subtitle: String {
        switch self {
        // The people you added — not everyone holding your number, which is an
        // audience you could never close.
        case .contacts: return "Everyone you've added"
        case .circles: return "Only the circles you pick"
        }
    }
}

struct WorldStoryRing: Identifiable, Equatable {
    var id: UUID { authorID }
    var authorID: UUID
    var authorName: String
    var authorAvatarURL: String?
    var allSeen: Bool
    var frames: [WorldPost]
}

struct WorldGraphContact: Identifiable, Equatable {
    let id: UUID
    var name: String
    var avatarURL: String?
    var phone: String?
    var alias: String?

    /// What the owner actually reads — their rename wins over the name the
    /// contact set for themselves.
    var effectiveName: String {
        if let alias, !alias.isEmpty { return alias }
        return name
    }
}

struct WorldRichProfile: Equatable {
    var bio: String = ""
    var gender: String = ""
    var city: String = ""
    var languages: [String] = []
    var education: String = ""
    var occupation: String = ""
    var interests: [String] = []
    var favouriteBooks: [String] = []
    var favouriteFilms: [String] = []
    var favouriteTv: [String] = []
    var favouriteSport: [String] = []
    var favouriteGames: [String] = []

    var isEmpty: Bool {
        bio.isEmpty && gender.isEmpty && city.isEmpty && languages.isEmpty
            && education.isEmpty && occupation.isEmpty && interests.isEmpty
            && favouriteBooks.isEmpty && favouriteFilms.isEmpty && favouriteTv.isEmpty
            && favouriteSport.isEmpty && favouriteGames.isEmpty
    }
}

// MARK: - Store

/// REST for the GojoMessages graph and its content. Separate from
/// `MessagingStore` (which owns conversations) because this is the private
/// *network* — the graph, its audiences and its posts — rather than chat.
@MainActor
final class WorldContentStore {
    static let shared = WorldContentStore()
    private init() {}

    // ---- contacts ---------------------------------------------------------

    func contacts() async throws -> [WorldGraphContact] {
        let dtos: [ContactDTO] = try await APIClient.shared.get("/v1/world/contacts")
        return dtos.map(map)
    }

    /// Adds by phone number. There is no handle equivalent, by design.
    func addContact(phone: String, alias: String? = nil) async throws -> WorldGraphContact {
        let dto: ContactDTO = try await APIClient.shared.post(
            "/v1/world/contacts", body: AddContactBody(phone: phone, alias: alias))
        return map(dto)
    }

    func removeContact(_ contactId: UUID) async throws {
        try await APIClient.shared.delete("/v1/world/contacts/\(contactId.uuidString.lowercased())")
    }

    private func map(_ dto: ContactDTO) -> WorldGraphContact {
        WorldGraphContact(id: dto.contactId,
                     name: dto.displayName ?? "Someone",
                     avatarURL: dto.avatarUrl,
                     phone: dto.phone,
                     alias: dto.alias)
    }

    // ---- circles ----------------------------------------------------------

    func circles() async throws -> [WorldCircle] {
        let dtos: [CircleDTO] = try await APIClient.shared.get("/v1/world/circles")
        return dtos.map(map)
    }

    func createCircle(name: String, colorHex: String?, members: [UUID]) async throws -> WorldCircle {
        let dto: CircleDTO = try await APIClient.shared.post(
            "/v1/world/circles",
            body: SaveCircleBody(name: name, colorHex: colorHex, memberIds: members))
        return map(dto)
    }

    func updateCircle(_ id: UUID, name: String, colorHex: String?,
                      members: [UUID]) async throws -> WorldCircle {
        let dto: CircleDTO = try await APIClient.shared.put(
            "/v1/world/circles/\(id.uuidString.lowercased())",
            body: SaveCircleBody(name: name, colorHex: colorHex, memberIds: members))
        return map(dto)
    }

    func deleteCircle(_ id: UUID) async throws {
        try await APIClient.shared.delete("/v1/world/circles/\(id.uuidString.lowercased())")
    }

    private func map(_ dto: CircleDTO) -> WorldCircle {
        WorldCircle(id: dto.id, name: dto.name,
                    memberIDs: dto.memberIds ?? [],
                    colorHex: dto.colorHex ?? "3A3A3C")
    }

    // ---- rich profile -----------------------------------------------------

    func myProfile() async throws -> WorldRichProfile {
        let dto: WorldRichProfileDTO = try await APIClient.shared.get("/v1/world/profile")
        return map(dto)
    }

    @discardableResult
    func updateProfile(_ profile: WorldRichProfile) async throws -> WorldRichProfile {
        let body = WorldRichProfileDTO(
            bio: profile.bio, gender: profile.gender, city: profile.city,
            languages: profile.languages, education: profile.education,
            occupation: profile.occupation, interests: profile.interests,
            favouriteBooks: profile.favouriteBooks, favouriteFilms: profile.favouriteFilms,
            favouriteTv: profile.favouriteTv, favouriteSport: profile.favouriteSport,
            favouriteGames: profile.favouriteGames)
        let dto: WorldRichProfileDTO = try await APIClient.shared.put("/v1/world/profile", body: body)
        return map(dto)
    }

    func contactProfile(_ contactId: UUID) async throws -> WorldContactProfileDTO {
        try await APIClient.shared.get("/v1/world/profile/\(contactId.uuidString.lowercased())")
    }

    private func map(_ dto: WorldRichProfileDTO) -> WorldRichProfile {
        WorldRichProfile(
            bio: dto.bio ?? "", gender: dto.gender ?? "", city: dto.city ?? "",
            languages: dto.languages ?? [], education: dto.education ?? "",
            occupation: dto.occupation ?? "", interests: dto.interests ?? [],
            favouriteBooks: dto.favouriteBooks ?? [], favouriteFilms: dto.favouriteFilms ?? [],
            favouriteTv: dto.favouriteTv ?? [], favouriteSport: dto.favouriteSport ?? [],
            favouriteGames: dto.favouriteGames ?? [])
    }

    // ---- content ----------------------------------------------------------

    func feed() async throws -> (stories: [WorldStoryRing], posts: [WorldPost]) {
        let dto: WorldFeedDTO = try await APIClient.shared.get("/v1/world/feed")
        let rings = dto.stories.map { group in
            WorldStoryRing(authorID: group.authorId,
                           authorName: group.authorName ?? "Someone",
                           authorAvatarURL: group.authorAvatarUrl,
                           allSeen: group.allSeen,
                           frames: group.frames.map(map))
        }
        return (rings, dto.posts.map(map))
    }

    func publish(kind: String, text: String?, imageURLs: [String],
                 audience: WorldPostAudience, circleIDs: [UUID]) async throws -> WorldPost {
        let media = imageURLs.map {
            WorldMediaItemDTO(imageUrl: $0, videoUrl: nil, isVideo: false, durationLabel: nil)
        }
        // A post with more than one image *is* a carousel — the re-spec names all
        // three kinds, and deriving it here is what stops `carousel` being a kind
        // the server accepts and nothing ever sends. Stories stay stories.
        let resolvedKind = (kind == "post" && imageURLs.count > 1) ? "carousel" : kind
        let dto: WorldContentDTO = try await APIClient.shared.post(
            "/v1/world/content",
            body: PublishContentBody(kind: resolvedKind, text: text,
                                     mediaItems: media.isEmpty ? nil : media,
                                     audience: audience.rawValue,
                                     circleIds: audience == .circles ? circleIDs : nil))
        return map(dto)
    }

    func delete(_ contentId: UUID) async throws {
        try await APIClient.shared.delete("/v1/world/content/\(contentId.uuidString.lowercased())")
    }

    func mine(kind: String = "post") async throws -> [WorldPost] {
        let dtos: [WorldContentDTO] = try await APIClient.shared
            .get("/v1/world/content/mine?kind=\(kind)")
        return dtos.map(map)
    }

    /// What this person published *to you*. The server answers from your own
    /// feed, so it can only ever return what they actually sent you.
    func content(by authorID: UUID, kind: String = "post") async throws -> [WorldPost] {
        let dtos: [WorldContentDTO] = try await APIClient.shared
            .get("/v1/world/content/by/\(authorID.uuidString.lowercased())?kind=\(kind)")
        return dtos.map(map)
    }

    func markSeen(_ contentId: UUID) async throws {
        try await APIClient.shared.post("/v1/world/content/\(contentId.uuidString.lowercased())/seen")
    }

    private func map(_ dto: WorldContentDTO) -> WorldPost {
        let images = (dto.mediaItems ?? []).compactMap { $0.imageUrl }
        return WorldPost(
            id: dto.id,
            authorID: dto.authorId,
            authorName: dto.authorName ?? "Someone",
            authorAvatarURL: dto.authorAvatarUrl,
            kind: dto.kind,
            text: dto.text ?? "",
            imageURLs: images,
            createdAt: BackendDate.parse(dto.createdAt) ?? Date(),
            expiresAt: dto.expiresAt.flatMap { BackendDate.parse($0) },
            seen: dto.seen ?? false,
            audience: dto.audience.flatMap { WorldPostAudience(rawValue: $0) },
            circleIDs: dto.circleIds ?? [])
    }
}
