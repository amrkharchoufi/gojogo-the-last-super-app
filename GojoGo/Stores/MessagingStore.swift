import SwiftUI

/// Messaging-module API surface (My World) plus DTO→UI-model mapping. Server
/// UUIDs are reused as WorldConversation/WorldMessage ids, so a mutation can
/// address the backend directly. `liveConversationIds` lets AppState route a
/// send to the API. Every thread is a live one now.
@MainActor
final class MessagingStore {

    static let shared = MessagingStore()

    var myProfileId: UUID?

    /// Conversations confirmed to exist on the backend.
    private(set) var liveConversationIds: Set<UUID> = []
    /// Cached participants per conversation — used to name poll voters / senders.
    private var participantsByConversation: [UUID: [ParticipantDTO]] = [:]
    /// Phone numbers learned from `by-phone` lookups. There's no profileId→phone
    /// endpoint, so this is the only way the contact page can offer a call.
    private var phoneByProfile: [UUID: String] = [:]

    /// Fired when a peer's identity key turns out to have changed — a reinstall,
    /// or a substituted key, and this device cannot tell the two apart.
    /// `AppState` answers with the neutral in-thread line. A callback rather
    /// than a direct call because the discovery happens deep in the wire→model
    /// mapping, which has no business knowing about conversations on screen.
    var peerIdentityChanged: ((UUID, UUID) -> Void)?

    func isLive(_ conversationId: UUID) -> Bool {
        liveConversationIds.contains(conversationId)
    }

    /// Everyone in a live thread, as the server last described them.
    func participants(in conversationId: UUID) -> [ParticipantDTO] {
        participantsByConversation[conversationId] ?? []
    }

    /// The other side of a 1:1 thread (nil for groups or unknown threads).
    func otherParticipant(in conversationId: UUID) -> ParticipantDTO? {
        let others = participants(in: conversationId).filter { $0.id != myProfileId }
        return others.count == 1 ? others.first : nil
    }

    func reset() {
        myProfileId = nil
        liveConversationIds = []
        participantsByConversation = [:]
        phoneByProfile = [:]
        // Renames are per-account: leaving them behind would show the last
        // person's private names to whoever signs in next.
        aliasByContact = [:]
    }

    // MARK: REST

    func fetchConversations() async throws -> [WorldConversation] {
        let dtos: [ConversationDTO] = try await APIClient.shared.get("/v1/conversations")
        return dtos.map { map($0) }
    }

    func createConversation(participantIds: [UUID], title: String?,
                            circleId: UUID? = nil,
                            background: WorldChatBackground = .none) async throws -> WorldConversation {
        let body = CreateConversationBody(
            participantIds: participantIds, title: title, circleId: circleId,
            background: background == .none ? nil : background.rawValue)
        let dto: ConversationDTO = try await APIClient.shared.post("/v1/conversations", body: body)
        return map(dto)
    }

    func fetchMessages(_ conversationId: UUID, before: String? = nil, limit: Int = 30) async throws
        -> (messages: [WorldMessage], nextBefore: String?, peerReadMessageId: UUID?) {
        var path = "/v1/conversations/\(conversationId.uuidString.lowercased())/messages?limit=\(limit)"
        if let before,
           let encoded = before.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&before=\(encoded)"
        }
        let page: MessagesPageDTO = try await APIClient.shared.get(path)
        // Server returns newest-first; the chat renders oldest-first.
        return (page.messages.reversed().map { map($0) }, page.nextBefore, page.peerReadMessageId)
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

    func setPinned(_ conversationId: UUID, pinned: Bool) async throws {
        try await APIClient.shared.post(
            "/v1/conversations/\(conversationId.uuidString.lowercased())/pin?pinned=\(pinned)")
    }

    /// Leaves (and for a 1:1, removes) the conversation server-side.
    func leave(_ conversationId: UUID) async throws {
        try await APIClient.shared.delete("/v1/conversations/\(conversationId.uuidString.lowercased())")
        liveConversationIds.remove(conversationId)
        participantsByConversation[conversationId] = nil
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
        let user: WorldUserDTO = try await APIClient.shared.get("/v1/world/by-phone/\(encoded)")
        phoneByProfile[user.profileId] = user.phone ?? phone
        return user
    }

    /// Known phone number for a World user, if we've ever resolved one.
    func phone(of profileId: UUID) -> String? { phoneByProfile[profileId] }

    // MARK: Contact aliases (private per-viewer renames)

    /// Every rename this account has made. Cached by `AppState` and applied at
    /// render time — the wire deliberately keeps carrying real names, because a
    /// socket payload is one object broadcast to every participant and can't
    /// carry a name that differs per viewer.
    func aliases() async throws -> [ContactAliasDTO] {
        try await APIClient.shared.get("/v1/world/aliases")
    }

    /// Renames a contact for this account only. A nil or blank alias clears it.
    @discardableResult
    func setAlias(_ contactId: UUID, to alias: String?) async throws -> ContactAliasDTO {
        try await APIClient.shared.put(
            "/v1/world/aliases/\(contactId.uuidString.lowercased())",
            body: SetContactAliasBody(alias: alias))
    }

    // MARK: Mapping

    /// Private renames, `contactId -> alias`, mirrored from `AppState.worldAliases`.
    /// Held here because this is the wire->model boundary: applying the lens once,
    /// where the server's names become app models, means every surface that
    /// renders a name picks the rename up without knowing it exists.
    var aliasByContact: [UUID: String] = [:]

    /// The name this account knows someone by — their private rename if there is
    /// one, otherwise whatever the server said.
    func aliasedName(for id: UUID?, fallback: String?) -> String? {
        if let id, let alias = aliasByContact[id] { return alias }
        return fallback
    }

    func map(_ dto: ConversationDTO) -> WorldConversation {
        liveConversationIds.insert(dto.id)
        participantsByConversation[dto.id] = dto.participants
        let other = dto.participants.first { $0.id != myProfileId }
        // A rename wins over every server-supplied name for a 1:1. A group title
        // names the thread rather than a person, so it is left alone.
        let renamed = dto.isGroup ? nil : other.flatMap { aliasByContact[$0.id] }
        // `dto.title` is one string every participant reads, so it can only ever
        // name a *group*. A 1:1 is named after the person you're talking to, and
        // each side resolves that for itself: honouring a stored title here would
        // show whoever the creator named the thread after — on a thread somebody
        // else started, that is your own name. Older threads still carry such a
        // title, so it is ignored rather than trusted as a fallback.
        let storedTitle: String? = dto.isGroup ? dto.title : nil
        let title = renamed
            ?? storedTitle
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
            background: WorldChatBackground(rawValue: dto.background ?? "none") ?? .none,
            listingContext: dto.context.map(listingContext))
    }

    private func listingContext(_ dto: ConversationContextDTO) -> WorldListingContext {
        WorldListingContext(
            kind: dto.kind,
            listingID: dto.kind == "listing" ? UUID(uuidString: dto.refId) : nil,
            title: dto.title,
            subtitle: dto.subtitle,
            imageURL: dto.imageUrl)
    }

    func map(_ dto: MessageDTO) -> WorldMessage {
        let mine = dto.senderId == myProfileId
        // Envelope messages carry their content opaquely; everything below
        // reads from the opened payload instead of the wire's own fields. A
        // message with no envelope is legacy plaintext, mapped exactly as
        // it always was.
        let payload = openedEnvelope(dto)
        let kind = kind(from: payload?.kind ?? dto.kind)
        let firstImage = dto.mediaItems?.first { !$0.isVideo }
        let firstVideo = dto.mediaItems?.first { $0.isVideo }
        // Audio rides in the media item's file slot; a pin rides there as a geo: URI.
        let audioURL = kind == .audio ? dto.mediaItems?.first?.videoUrl : nil
        let place = kind == .location ? WorldLocationPayload(dto.mediaItems?.first) : nil
        let movieURL = kind == .video ? firstVideo?.videoUrl : nil
        let carousel = (dto.mediaItems ?? []).map {
            // Poster (imageUrl) renders in the bubble; videoUrl is the movie the
            // viewer plays when the slide is opened.
            WorldCarouselItem(imageData: Data(), isVideo: $0.isVideo,
                              durationLabel: $0.durationLabel,
                              imageURL: $0.imageUrl,
                              videoURL: $0.isVideo ? $0.videoUrl : nil)
        }
        let reactions = dto.reactions.map {
            WorldReaction(tapback: WorldTapback(rawValue: $0.tapback) ?? .heart,
                          fromUser: $0.userId == myProfileId)
        }
        let reply: WorldReplySnippet?
        if let payload, payload.replyPreview != nil || payload.replyAuthorName != nil {
            // The envelope's quote card is self-contained — the receiver never
            // needs the server's copy of the replied-to message.
            reply = WorldReplySnippet(
                authorName: aliasedName(for: payload.replyAuthorId,
                                        fallback: payload.replyAuthorName) ?? "",
                preview: payload.replyPreview ?? "",
                fromUser: payload.replyAuthorId == myProfileId)
        } else {
            reply = dto.replyTo.map {
                // authorId is what carries the rename into the quote card. Snippets
                // written before that field existed have none, and fall back to the
                // name stored with the message.
                WorldReplySnippet(authorName: aliasedName(for: $0.authorId, fallback: $0.authorName) ?? "",
                                  preview: $0.preview ?? "", fromUser: false)
            }
        }
        return WorldMessage(
            id: dto.id,
            kind: kind,
            text: payload?.latitude != nil ? (payload?.text ?? "")
                : (place?.name ?? payload?.text ?? dto.text ?? ""),
            fromUser: mine,
            fileName: payload?.fileName,
            fileMeta: payload?.fileMeta,
            readLabel: mine ? "Delivered" : nil,
            imageURL: firstImage?.imageUrl ?? firstVideo?.imageUrl,
            durationLabel: payload?.durationLabel
                ?? (kind == .location ? nil : (firstImage ?? firstVideo)?.durationLabel),
            senderName: mine ? nil : aliasedName(for: dto.senderId, fallback: dto.senderName),
            carouselItems: carousel.count >= 2 ? carousel : [],
            reactions: reactions,
            replyTo: reply,
            poll: dto.poll.map { poll(from: $0, in: dto.conversationId) },
            audioURL: audioURL,
            videoURL: movieURL,
            latitude: payload?.latitude ?? place?.latitude,
            longitude: payload?.longitude ?? place?.longitude,
            isUndecryptable: payload?.kind == Self.undecryptableKind)
    }

    /// Opens an envelope message's payload; nil for legacy plaintext.
    ///
    /// The vault comes first and that ordering is load-bearing, not an
    /// optimisation. A sealed (v2) body decrypts exactly once — the message key
    /// is deleted on use — and this method runs again for the same message on
    /// every refetch, every socket echo and every poll update. Asking libsignal
    /// a second time would throw and lose the message permanently.
    ///
    /// Our own outgoing messages are here for the same reason from the other
    /// side: they were sealed to the *peer's* ratchet and this device cannot
    /// open them at all. `envelopeBody` banks the payload under the client id
    /// at seal time; the first echo re-keys it onto the server's id, and
    /// fetched pages carry `clientId` so a relaunch mid-send still resolves.
    ///
    /// A payload this build cannot open still returns — as a text bubble that
    /// says so. Silence would read as a lost message, and the message is not
    /// lost; this build just can't represent it. Failures are never banked:
    /// some are transient (files locked before first unlock, profile id not
    /// loaded yet) and would otherwise become permanent.
    private func openedEnvelope(_ dto: MessageDTO) -> WorldEnvelopePayload? {
        guard dto.kind == "encrypted" else { return nil }
        let vault = WorldEnvelopeVault.shared
        if let banked = vault.payload(for: dto.id, in: dto.conversationId) {
            // Cheap and idempotent — the key store is persisted, but the vault
            // is the record of what was actually opened, so re-registering from
            // it is what keeps the two from drifting.
            if let keys = banked.mediaKeys { WorldMediaKeyStore.shared.register(keys) }
            return banked
        }
        if let clientId = dto.clientId,
           let banked = vault.payload(for: clientId, in: dto.conversationId) {
            vault.store(banked, for: dto.id, in: dto.conversationId)
            if let keys = banked.mediaKeys { WorldMediaKeyStore.shared.register(keys) }
            return banked
        }
        guard let version = dto.envelopeVersion, let body = dto.cipherBody else {
            return WorldEnvelopePayload(kind: "text", text: "Message can't be displayed.")
        }
        // Sealed to a session with the *sender*. Our own messages never reach
        // here — they resolve from the vault above or not at all.
        do {
            let payload = try WorldEnvelope.open(
                version: version, body: body, from: dto.senderId,
                identityChanged: { [weak self] in
                    self?.peerIdentityChanged?(dto.conversationId, dto.senderId)
                })
            vault.store(payload, for: dto.id, in: dto.conversationId)
            // Phase D: the attachment keys came out of the same sealed body as
            // the text. Registering them here — at the wire boundary, before
            // any view has asked for a URL — is what lets `ImageCache` decrypt
            // without every media surface in the app knowing keys exist.
            if let keys = payload.mediaKeys { WorldMediaKeyStore.shared.register(keys) }
            return payload
        } catch WorldEnvelope.EnvelopeError.unsupportedVersion {
            return WorldEnvelopePayload(
                kind: "text",
                text: "This message needs a newer version of GojoGo.")
        } catch {
            #if DEBUG
            print("Envelope open failed (\(dto.id)): \(error)")
            #endif
            return WorldEnvelopePayload(
                kind: Self.undecryptableKind,
                text: "This message couldn't be decrypted.")
        }
    }

    /// Marks a payload this device couldn't open. Not a wire kind — nothing
    /// sends it; `kind(from:)` falls through to `.text` so it renders as the
    /// sentence above, and `map` turns it into `WorldMessage.isUndecryptable`
    /// so the merge can prefer the archive's already-opened copy.
    private static let undecryptableKind = "undecryptable"

    private func kind(from raw: String) -> WorldMessageKind {
        switch raw {
        case "emoji": return .emoji
        case "photo": return .photo
        case "video": return .video
        case "carousel": return .carousel
        case "sticker": return .sticker
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
