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

struct ReplySnippetDTO: Codable {
    var messageId: UUID
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
