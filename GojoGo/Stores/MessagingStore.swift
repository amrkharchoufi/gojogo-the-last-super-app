import SwiftUI

/// Messaging-module API surface (My World) plus DTO→UI-model mapping. Server
/// UUIDs are reused as WorldConversation/WorldMessage ids, so a mutation can
/// address the backend directly. `liveConversationIds` lets AppState route a
/// send to the API (live thread) or the local simulator (SampleData thread).
@MainActor
final class MessagingStore {

    static let shared = MessagingStore()

    var myProfileId: UUID?

    /// Conversations that exist on the backend (vs. SampleData demo threads).
    private(set) var liveConversationIds: Set<UUID> = []
    /// Cached participants per conversation — used to name poll voters / senders.
    private var participantsByConversation: [UUID: [ParticipantDTO]] = [:]

    func isLive(_ conversationId: UUID) -> Bool {
        liveConversationIds.contains(conversationId)
    }

    func reset() {
        myProfileId = nil
        liveConversationIds = []
        participantsByConversation = [:]
    }

    // MARK: REST

    func fetchConversations() async throws -> [WorldConversation] {
        let dtos: [ConversationDTO] = try await APIClient.shared.get("/v1/conversations")
        return dtos.map { map($0) }
    }

    func createConversation(participantIds: [UUID], title: String?,
                            circleId: UUID? = nil) async throws -> WorldConversation {
        let body = CreateConversationBody(
            participantIds: participantIds, title: title, circleId: circleId, background: nil)
        let dto: ConversationDTO = try await APIClient.shared.post("/v1/conversations", body: body)
        return map(dto)
    }

    func fetchMessages(_ conversationId: UUID, before: String? = nil, limit: Int = 30) async throws
        -> (messages: [WorldMessage], nextBefore: String?) {
        var path = "/v1/conversations/\(conversationId.uuidString.lowercased())/messages?limit=\(limit)"
        if let before,
           let encoded = before.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&before=\(encoded)"
        }
        let page: MessagesPageDTO = try await APIClient.shared.get(path)
        // Server returns newest-first; the chat renders oldest-first.
        return (page.messages.reversed().map { map($0) }, page.nextBefore)
    }

    @discardableResult
    func send(_ conversationId: UUID, body: SendMessageBody) async throws -> WorldMessage {
        let dto: MessageDTO = try await APIClient.shared
            .post("/v1/conversations/\(conversationId.uuidString.lowercased())/messages", body: body)
        return map(dto)
    }

    func react(_ conversationId: UUID, message messageId: UUID, tapback: WorldTapback) async throws {
        try await APIClient.shared.postNoContent(
            "/v1/conversations/\(conversationId.uuidString.lowercased())/messages/\(messageId.uuidString.lowercased())/reactions",
            body: ReactBody(tapback: tapback.rawValue))
    }

    func unreact(_ conversationId: UUID, message messageId: UUID) async throws {
        try await APIClient.shared.delete(
            "/v1/conversations/\(conversationId.uuidString.lowercased())/messages/\(messageId.uuidString.lowercased())/reactions")
    }

    @discardableResult
    func votePoll(_ conversationId: UUID, message messageId: UUID, option optionId: UUID) async throws
        -> WorldMessage {
        let dto: MessageDTO = try await APIClient.shared.post(
            "/v1/conversations/\(conversationId.uuidString.lowercased())/messages/\(messageId.uuidString.lowercased())/poll/vote",
            body: VotePollBody(optionId: optionId))
        return map(dto)
    }

    func markRead(_ conversationId: UUID, lastMessageId: UUID) async throws {
        try await APIClient.shared.postNoContent(
            "/v1/conversations/\(conversationId.uuidString.lowercased())/read",
            body: MarkReadBody(lastReadMessageId: lastMessageId))
    }

    func sendTyping(_ conversationId: UUID) async throws {
        try await APIClient.shared.post(
            "/v1/conversations/\(conversationId.uuidString.lowercased())/typing")
    }

    // MARK: World identity / setup

    func worldMe() async throws -> WorldProfileDTO {
        try await APIClient.shared.get("/v1/world/me")
    }

    @discardableResult
    func worldStartPhone(_ phone: String) async throws -> Bool {
        let dto: StartPhoneResponseDTO = try await APIClient.shared
            .post("/v1/world/phone/start", body: StartPhoneBody(phone: phone))
        return dto.sent
    }

    func worldVerifyPhone(_ phone: String, code: String) async throws {
        try await APIClient.shared.postNoContent(
            "/v1/world/phone/verify", body: VerifyPhoneBody(phone: phone, code: code))
    }

    func worldUpdateProfile(displayName: String?, avatarUrl: String?) async throws -> WorldProfileDTO {
        try await APIClient.shared.put(
            "/v1/world/me", body: UpdateWorldProfileBody(displayName: displayName, avatarUrl: avatarUrl))
    }

    func worldByPhone(_ phone: String) async throws -> WorldUserDTO {
        let encoded = phone.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? phone
        return try await APIClient.shared.get("/v1/world/by-phone/\(encoded)")
    }

    // MARK: Mapping

    func map(_ dto: ConversationDTO) -> WorldConversation {
        liveConversationIds.insert(dto.id)
        participantsByConversation[dto.id] = dto.participants
        let other = dto.participants.first { $0.id != myProfileId }
        let title = dto.title
            ?? other?.displayName
            ?? other.map { "@\($0.handle ?? "user")" }
            ?? "Conversation"
        let handleSeed = other?.handle ?? dto.title ?? dto.id.uuidString
        return WorldConversation(
            id: dto.id,
            circleID: dto.circleId,
            title: title,
            preview: dto.preview ?? "",
            timeAgo: BackendDate.relative(dto.lastActivityAt),
            unread: dto.unread,
            isGroup: dto.isGroup,
            pinned: dto.pinned,
            avatarURL: other?.avatarUrl,
            avatarGradient: SocialStore.gradient(for: handleSeed),
            messages: [],
            lastActivityAt: BackendDate.parse(dto.lastActivityAt) ?? Date(),
            background: WorldChatBackground(rawValue: dto.background ?? "none") ?? .none)
    }

    func map(_ dto: MessageDTO) -> WorldMessage {
        let mine = dto.senderId == myProfileId
        let firstImage = dto.mediaItems?.first { !$0.isVideo }
        let firstVideo = dto.mediaItems?.first { $0.isVideo }
        let carousel = (dto.mediaItems ?? []).map {
            // Poster (imageUrl) is what renders in the bubble for both photo and
            // video items; the video file (videoUrl) is for future playback.
            WorldCarouselItem(imageData: Data(), isVideo: $0.isVideo,
                              durationLabel: $0.durationLabel,
                              imageURL: $0.imageUrl ?? $0.videoUrl)
        }
        let reactions = dto.reactions.map {
            WorldReaction(tapback: WorldTapback(rawValue: $0.tapback) ?? .heart,
                          fromUser: $0.userId == myProfileId)
        }
        let reply = dto.replyTo.map {
            WorldReplySnippet(authorName: $0.authorName ?? "", preview: $0.preview ?? "", fromUser: false)
        }
        return WorldMessage(
            id: dto.id,
            kind: kind(from: dto.kind),
            text: dto.text ?? "",
            fromUser: mine,
            readLabel: mine ? "Delivered" : nil,
            imageURL: firstImage?.imageUrl ?? firstVideo?.imageUrl,
            durationLabel: (firstImage ?? firstVideo)?.durationLabel,
            senderName: mine ? nil : dto.senderName,
            carouselItems: carousel.count >= 2 ? carousel : [],
            reactions: reactions,
            replyTo: reply,
            poll: dto.poll.map { poll(from: $0, in: dto.conversationId) })
    }

    private func kind(from raw: String) -> WorldMessageKind {
        switch raw {
        case "emoji": return .emoji
        case "photo": return .photo
        case "video": return .video
        case "carousel": return .carousel
        case "audio": return .audio
        case "location": return .location
        case "poll": return .poll
        case "file": return .file
        case "system": return .system
        case "timestamp": return .timestamp
        default: return .text
        }
    }

    private func poll(from dto: PollDTO, in conversationId: UUID) -> WorldPoll {
        let participants = participantsByConversation[conversationId] ?? []
        func voterLabel(_ id: UUID) -> String {
            if id == myProfileId { return "You" }
            let p = participants.first { $0.id == id }
            return p?.displayName ?? p.map { "@\($0.handle ?? "user")" } ?? "Someone"
        }
        let options = dto.options.map {
            WorldPollOption(id: $0.id, text: $0.text, voters: ($0.voters ?? []).map(voterLabel))
        }
        return WorldPoll(question: dto.question, options: options, allowsMultiple: dto.allowsMultiple)
    }
}
