import Foundation

// Typed mirrors of the backend `messaging` module DTOs (My World). Timestamps
// stay ISO-8601 strings; parse via `BackendDate`. Server UUIDs are reused as the
// UI model ids (same convention as SocialStore) so a WorldConversation/
// WorldMessage can address the backend directly.

struct ParticipantDTO: Decodable {
    var id: UUID
    var displayName: String?
    var handle: String?
    var avatarUrl: String?
}

struct WorldMediaItemDTO: Codable {
    var imageUrl: String?
    var videoUrl: String?
    var isVideo: Bool
    var durationLabel: String?
}

/// A shared pin, carried inside the message's single media slot as a `geo:` URI
/// (`geo:33.5731,-7.5898`). The wire format has no coordinate fields and the
/// media item is passed through the backend untouched, so this keeps a real
/// location openable in Maps on the other side without a schema change.
struct WorldLocationPayload {
    var latitude: Double
    var longitude: Double
    var name: String

    private static let scheme = "geo:"

    var mediaItem: WorldMediaItemDTO {
        WorldMediaItemDTO(imageUrl: nil,
                          videoUrl: "\(Self.scheme)\(latitude),\(longitude)",
                          isVideo: false,
                          durationLabel: name.isEmpty ? nil : name)
    }

    init(latitude: Double, longitude: Double, name: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
    }

    init?(_ item: WorldMediaItemDTO?) {
        guard let raw = item?.videoUrl, raw.hasPrefix(Self.scheme) else { return nil }
        let parts = raw.dropFirst(Self.scheme.count).split(separator: ",")
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else {
            return nil
        }
        latitude = lat
        longitude = lon
        name = item?.durationLabel ?? "Location"
    }
}

struct ReplySnippetDTO: Codable {
    var messageId: UUID
    /// Who wrote the quoted message. Optional because snippets stored before this
    /// field existed decode without it — those fall back to `authorName`. It's
    /// what lets a private rename reach the quote card, not just the bubble.
    var authorId: UUID?
    var authorName: String?
    var preview: String?
}

struct ReactionDTO: Decodable {
    var userId: UUID
    var tapback: String
}

struct PollOptionDTO: Codable {
    var id: UUID
    var text: String
    var voters: [UUID]?
}

struct PollDTO: Codable {
    var question: String
    var options: [PollOptionDTO]
    var allowsMultiple: Bool
}

struct MessageDTO: Decodable {
    var id: UUID
    var conversationId: UUID
    var senderId: UUID
    var senderName: String?
    var kind: String
    var text: String?
    var mediaItems: [WorldMediaItemDTO]?
    var poll: PollDTO?
    var replyTo: ReplySnippetDTO?
    var reactions: [ReactionDTO]
    var createdAt: String
    var scheduledAt: String?
    var clientId: UUID?
}

struct MessagesPageDTO: Decodable {
    var messages: [MessageDTO]
    var nextBefore: String?
    /// Newest message every other participant has read up to — the "Read"
    /// high-water mark for the caller's own messages. Nil until everyone reads.
    var peerReadMessageId: UUID?
}

/// A vertical's reference card on a conversation (a listing today; a delivery
/// order or ride later). The messaging module carries it opaquely; `kind`/`refId`
/// let the client resolve the real object, and title/subtitle/imageUrl are the
/// pre-rendered card so no cross-module read is needed to draw it.
struct ConversationContextDTO: Decodable {
    var kind: String
    var refId: String
    var title: String
    var subtitle: String?
    var imageUrl: String?
}

struct ConversationDTO: Decodable {
    var id: UUID
    var type: String
    var title: String?
    var isGroup: Bool
    var participants: [ParticipantDTO]
    var circleId: UUID?
    var background: String?
    var preview: String?
    var lastActivityAt: String
    var unread: Int
    var pinned: Bool
    var muted: Bool
    var context: ConversationContextDTO?
}

// MARK: - Request bodies

struct CreateConversationBody: Encodable {
    var participantIds: [UUID]
    var title: String?
    var circleId: UUID?
    var background: String?
}

struct SendMessageBody: Encodable {
    var kind: String
    var text: String?
    var mediaItems: [WorldMediaItemDTO]?
    var poll: PollDTO?
    var replyToMessageId: UUID?
    var clientId: UUID?
    var scheduledAt: String?
}

struct ReactBody: Encodable {
    var tapback: String
}

struct VotePollBody: Encodable {
    var optionId: UUID
}

struct MarkReadBody: Encodable {
    var lastReadMessageId: UUID
}

// MARK: - My World identity / setup (WhatsApp-style phone-verified profile)

struct WorldProfileDTO: Decodable {
    var setupComplete: Bool
    var phone: String?
    var displayName: String?
    var avatarUrl: String?
}

struct StartPhoneBody: Encodable {
    var phone: String
}

struct StartPhoneResponseDTO: Decodable {
    var sent: Bool
}

struct VerifyPhoneBody: Encodable {
    var phone: String
    var code: String
}

struct UpdateWorldProfileBody: Encodable {
    var displayName: String?
    var avatarUrl: String?
}

struct WorldUserDTO: Decodable {
    var profileId: UUID
    var displayName: String?
    var avatarUrl: String?
    var phone: String?
}

/// One private rename. The alias is the viewer's own — the server never shows it
/// to the person renamed, and the wire always carries their real name alongside.
struct ContactAliasDTO: Decodable {
    var contactId: UUID
    var alias: String?
}

struct SetContactAliasBody: Encodable {
    var alias: String?
}

// MARK: - WebSocket fan-out envelope

/// One server->client event over the World socket. `type` selects which of the
/// optional payloads is populated (see MessagingService fan-out).
struct WorldSocketEvent: Decodable {
    var type: String
    var message: MessageDTO?
    var conversation: ConversationDTO?
    var conversationId: UUID?
    var messageId: UUID?
    var userId: UUID?
    var tapback: String?
    var lastReadMessageId: UUID?
}
