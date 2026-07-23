import SwiftUI

// MARK: - My World live messaging (Phase 2)
//
// Bridges AppState's existing My World surface onto the deployed `messaging`
// backend. Live threads (MessagingStore.liveConversationIds) send over REST and
// receive over the WebSocket; SampleData demo threads keep the local iMessage
// simulation (canned auto-reply) untouched. The existing view code is unchanged
// — these methods reuse the same `worldConversations` model the views observe.

extension AppState {

    /// Loads live conversations and opens the real-time socket. Called from
    /// `connectBackend()` once the profile session exists.
    func connectMessaging() async {
        MessagingStore.shared.myProfileId = SocialStore.shared.myProfileId
        WorldSocket.shared.onEvent = { [weak self] event in
            self?.handleWorldSocketEvent(event)
        }
        await loadWorldProfile()
        do {
            let live = try await MessagingStore.shared.fetchConversations()
            mergeLiveConversations(live)
            WorldSocket.shared.connect()
        } catch {
            #if DEBUG
            print("Messaging connect failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: My World setup (phone-verified identity)

    /// True once the backend has answered and the caller hasn't finished setup.
    /// Only gates when connected — offline falls back to the local demo.
    var needsWorldSetup: Bool {
        backendConnected && worldSetupLoaded && !worldSetupComplete
    }

    func loadWorldProfile() async {
        do {
            let me = try await MessagingStore.shared.worldMe()
            worldSetupComplete = me.setupComplete
            worldPhone = me.phone
            worldSetupAvatarURL = me.avatarUrl
            if let name = me.displayName, worldSetupName.isEmpty { worldSetupName = name }
            if let phone = me.phone, worldSetupPhone.isEmpty { worldSetupPhone = phone }
            // Resume mid-setup: phone known but name missing → jump to profile.
            if !me.setupComplete, me.phone != nil { worldSetupStep = .profile }
            worldSetupLoaded = true
        } catch {
            // Treat a failure as "not set up yet" so a connected user still
            // sees onboarding rather than a broken empty list.
            worldSetupLoaded = true
            #if DEBUG
            print("World profile load failed: \(error.localizedDescription)")
            #endif
        }
    }

    func advanceWorldFromIntro() {
        worldSetupError = nil
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { worldSetupStep = .phone }
    }

    func backWorldSetup() {
        worldSetupError = nil
        guard worldSetupStep != .intro else { return }
        let previous = WorldSetupStep(rawValue: worldSetupStep.rawValue - 1) ?? .intro
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { worldSetupStep = previous }
    }

    func worldSubmitPhone() {
        guard !worldSetupBusy else { return }
        let phone = worldSetupPhone.trimmingCharacters(in: .whitespaces)
        guard phone.filter(\.isNumber).count >= 8 else {
            worldSetupError = "Enter your phone number with country code."
            return
        }
        worldSetupBusy = true
        worldSetupError = nil
        Task {
            defer { worldSetupBusy = false }
            do {
                try await MessagingStore.shared.worldStartPhone(phone)
                worldSetupCode = ""
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { worldSetupStep = .code }
            } catch {
                worldSetupError = (error as? APIClient.APIError)?.errorDescription
                    ?? "Couldn't send the code. Try again."
            }
        }
    }

    func worldResendCode() {
        Task { try? await MessagingStore.shared.worldStartPhone(worldSetupPhone.trimmingCharacters(in: .whitespaces)) }
    }

    func worldSubmitCode() {
        guard !worldSetupBusy else { return }
        let code = worldSetupCode.trimmingCharacters(in: .whitespaces)
        guard code.count >= 4 else {
            worldSetupError = "Enter the code we texted you."
            return
        }
        worldSetupBusy = true
        worldSetupError = nil
        Task {
            defer { worldSetupBusy = false }
            do {
                try await MessagingStore.shared.worldVerifyPhone(
                    worldSetupPhone.trimmingCharacters(in: .whitespaces), code: code)
                worldPhone = worldSetupPhone.trimmingCharacters(in: .whitespaces)
                if worldSetupName.isEmpty { worldSetupName = user.name }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { worldSetupStep = .profile }
            } catch {
                worldSetupError = (error as? APIClient.APIError)?.errorDescription ?? "Incorrect code."
            }
        }
    }

    func worldSaveProfile() {
        guard !worldSetupBusy else { return }
        let name = worldSetupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 2 else {
            worldSetupError = "Pick a name for My World."
            return
        }
        worldSetupBusy = true
        worldSetupError = nil
        Task {
            defer { worldSetupBusy = false }
            do {
                var avatarUrl = worldSetupAvatarURL
                if let data = worldSetupAvatarData {
                    avatarUrl = try await uploadWorldImage(data)
                }
                let me = try await MessagingStore.shared.worldUpdateProfile(
                    displayName: name, avatarUrl: avatarUrl)
                worldSetupComplete = me.setupComplete
                worldSetupAvatarURL = me.avatarUrl
                worldPhone = me.phone
                if me.setupComplete {
                    // Enter the real My World: pull live conversations, open socket.
                    withAnimation(.easeInOut(duration: 0.35)) { worldSetupStep = .intro }
                    await connectMessaging()
                }
            } catch {
                worldSetupError = (error as? APIClient.APIError)?.errorDescription
                    ?? "Couldn't save your profile. Try again."
            }
        }
    }

    /// Resolves several handles/phone numbers to real accounts and opens a live
    /// group conversation. Returns false unless at least two others resolve.
    func startLiveGroup(recipients: [String]) async -> Bool {
        guard backendConnected else { return false }
        var ids: [UUID] = []
        var names: [String] = []
        for entry in recipients {
            let isPhone = entry.allSatisfy { "+0123456789 -()".contains($0) }
            if isPhone {
                if let u = try? await MessagingStore.shared.worldByPhone(entry),
                   u.profileId != SocialStore.shared.myProfileId, !ids.contains(u.profileId) {
                    ids.append(u.profileId); names.append(u.displayName ?? "Member")
                }
            } else {
                let handle = entry.hasPrefix("@") ? String(entry.dropFirst()) : entry
                if let v = try? await ProfileStore.shared.view(handle: handle),
                   v.id != SocialStore.shared.myProfileId, !ids.contains(v.id) {
                    ids.append(v.id); names.append(v.name)
                }
            }
        }
        guard ids.count >= 2 else { return false }
        let title = names.prefix(3).joined(separator: ", ")
        do {
            let convo = try await MessagingStore.shared.createConversation(
                participantIds: ids, title: title)
            if worldConversations.firstIndex(where: { $0.id == convo.id }) == nil {
                worldConversations.insert(convo, at: 0)
            }
            openWorldConversation(convo.id)
            return true
        } catch {
            return false
        }
    }

    /// Resolves a verified phone to a World user and opens a live 1:1 thread.
    func startLiveConversation(phone raw: String) async -> Bool {
        guard backendConnected,
              let user = try? await MessagingStore.shared.worldByPhone(raw),
              user.profileId != SocialStore.shared.myProfileId else { return false }
        do {
            let convo = try await MessagingStore.shared.createConversation(
                participantIds: [user.profileId], title: user.displayName)
            if worldConversations.firstIndex(where: { $0.id == convo.id }) == nil {
                worldConversations.insert(convo, at: 0)
            }
            openWorldConversation(convo.id)
            return true
        } catch {
            return false
        }
    }

    /// Live threads become the source of truth for the Messages list; SampleData
    /// threads (no server id) stay below so the demo/composer still works.
    private func mergeLiveConversations(_ live: [WorldConversation]) {
        guard !live.isEmpty else { return }
        let liveIds = Set(live.map(\.id))
        var merged = live
        merged.append(contentsOf: worldConversations.filter { !liveIds.contains($0.id) })
        withAnimation(.easeOut(duration: 0.25)) { worldConversations = merged }
    }

    /// Fetches messages for a live thread the first time it's opened, then marks
    /// it read on the server. No-op for SampleData threads.
    func loadLiveConversationIfNeeded(_ id: UUID) {
        guard MessagingStore.shared.isLive(id) else { return }
        Task {
            do {
                let page = try await MessagingStore.shared.fetchMessages(id)
                if let i = worldConversations.firstIndex(where: { $0.id == id }) {
                    // Preserve any optimistic messages not yet echoed by the server.
                    let serverIds = Set(page.messages.map(\.id))
                    let pendingLocal = worldConversations[i].messages.filter {
                        !serverIds.contains($0.id) && $0.fromUser && $0.kind != .timestamp
                    }
                    worldConversations[i].messages = page.messages + pendingLocal
                }
                if let last = worldConversations.first(where: { $0.id == id })?.messages.last(where: {
                    $0.kind != .timestamp && $0.kind != .system
                }) {
                    try? await MessagingStore.shared.markRead(id, lastMessageId: last.id)
                }
            } catch {
                #if DEBUG
                print("Live message load failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: Outbound (called from deliverWorldMessage for live threads)

    func liveSend(_ msg: WorldMessage, in conversationId: UUID,
                  replyToId: UUID? = nil, scheduledAt: Date? = nil) {
        Task {
            do {
                var mediaItems: [WorldMediaItemDTO]? = nil
                switch msg.kind {
                case .photo:
                    if let data = msg.imageData, let url = try await uploadWorldImage(data) {
                        mediaItems = [WorldMediaItemDTO(imageUrl: url, videoUrl: nil,
                                                        isVideo: false, durationLabel: nil)]
                    }
                case .video:
                    // Upload the poster frame so the recipient's bubble renders
                    // (streamable in-chat playback = Phase 3 UGC video pipeline).
                    if let data = msg.imageData, let url = try await uploadWorldImage(data) {
                        mediaItems = [WorldMediaItemDTO(imageUrl: url, videoUrl: nil,
                                                        isVideo: true, durationLabel: msg.durationLabel)]
                    }
                case .carousel:
                    var items: [WorldMediaItemDTO] = []
                    for slide in msg.carouselItems {
                        if let url = try await uploadWorldImage(slide.imageData) {
                            items.append(WorldMediaItemDTO(imageUrl: url, videoUrl: nil,
                                                           isVideo: slide.isVideo,
                                                           durationLabel: slide.durationLabel))
                        }
                    }
                    mediaItems = items.isEmpty ? nil : items
                default:
                    break
                }
                let poll = msg.poll.map { local in
                    PollDTO(question: local.question,
                            options: local.options.map { PollOptionDTO(id: $0.id, text: $0.text, voters: []) },
                            allowsMultiple: local.allowsMultiple)
                }
                let body = SendMessageBody(
                    kind: wireKind(msg.kind), text: msg.text.isEmpty ? nil : msg.text,
                    mediaItems: mediaItems, poll: poll, replyToMessageId: replyToId,
                    clientId: msg.id, scheduledAt: scheduledAt.map { Self.iso8601($0) })
                _ = try await MessagingStore.shared.send(conversationId, body: body)
            } catch {
                #if DEBUG
                print("Live send failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private static func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private func uploadWorldImage(_ data: Data) async throws -> String? {
        let type = APIClient.imageContentType(for: data)
        let payload: Data
        if type == "image/jpeg" || type == "image/png" || type == "image/gif" {
            payload = data
        } else {
            payload = UIImage(data: data)?.jpegData(compressionQuality: 0.9) ?? data
        }
        let finalType = payload == data ? type : "image/jpeg"
        return try await APIClient.shared.uploadMedia(payload, contentType: finalType)
    }

    /// Sends a typing ping on a live thread, throttled to once per ~3s. Called
    /// from the composer's onChange; SampleData threads ignore it.
    func worldTypingChanged() {
        guard let id = selectedWorldConversationID, MessagingStore.shared.isLive(id),
              !worldDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let now = Date()
        if let last = worldLastTypingSentAt, now.timeIntervalSince(last) < 3 { return }
        worldLastTypingSentAt = now
        Task { try? await MessagingStore.shared.sendTyping(id) }
    }

    func liveReact(_ tapback: WorldTapback?, on messageID: UUID, in conversationID: UUID) {
        Task {
            do {
                if let tapback {
                    try await MessagingStore.shared.react(conversationID, message: messageID, tapback: tapback)
                } else {
                    try await MessagingStore.shared.unreact(conversationID, message: messageID)
                }
            } catch {
                #if DEBUG
                print("Live reaction failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func liveVotePoll(messageID: UUID, optionID: UUID, in conversationID: UUID) {
        Task {
            _ = try? await MessagingStore.shared.votePoll(conversationID, message: messageID, option: optionID)
        }
    }

    /// Resolves a handle to a real profile and opens a live 1:1 thread. Returns
    /// false when there's no matching account (caller falls back to the demo).
    func startLiveConversation(handle raw: String) async -> Bool {
        let handle = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
        guard backendConnected,
              let view = try? await ProfileStore.shared.view(handle: handle),
              view.id != SocialStore.shared.myProfileId else { return false }
        do {
            let convo = try await MessagingStore.shared.createConversation(
                participantIds: [view.id], title: nil)
            if let existing = worldConversations.firstIndex(where: { $0.id == convo.id }) {
                openWorldConversation(worldConversations[existing].id)
            } else {
                worldConversations.insert(convo, at: 0)
                openWorldConversation(convo.id)
            }
            return true
        } catch {
            #if DEBUG
            print("Start live conversation failed: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    // MARK: Inbound (WebSocket)

    func handleWorldSocketEvent(_ event: WorldSocketEvent) {
        switch event.type {
        case "message":
            if let dto = event.message { applyIncomingMessage(dto) }
        case "reaction":
            applyIncomingReaction(event)
        case "poll":
            if let dto = event.message { applyPollUpdate(dto) }
        case "read":
            applyReadReceipt(event)
        case "typing":
            applyTyping(event)
        case "conversation":
            if let dto = event.conversation { mergeLiveConversations([MessagingStore.shared.map(dto)]) }
        default:
            break
        }
    }

    private func applyIncomingMessage(_ dto: MessageDTO) {
        guard let i = worldConversations.firstIndex(where: { $0.id == dto.conversationId }) else {
            // First message of a thread we don't have yet — refresh the list.
            Task { if let live = try? await MessagingStore.shared.fetchConversations() {
                mergeLiveConversations(live)
            } }
            return
        }
        let mapped = MessagingStore.shared.map(dto)
        let mine = dto.senderId == SocialStore.shared.myProfileId
        withAnimation(.spring(response: 0.42, dampingFraction: 0.7)) {
            if mine, let clientId = dto.clientId,
               let j = worldConversations[i].messages.firstIndex(where: { $0.id == clientId }) {
                // Echo of our own optimistic bubble — adopt the server id.
                worldConversations[i].messages[j] = mapped
            } else if !worldConversations[i].messages.contains(where: { $0.id == mapped.id }) {
                worldConversations[i].messages.append(mapped)
                worldConversations[i].preview = mine ? "You: \(mapped.snippetText)" : mapped.snippetText
                if selectedWorldConversationID != dto.conversationId && !mine {
                    worldConversations[i].unread += 1
                }
            }
            worldConversations[i].lastActivityAt = BackendDate.parse(dto.createdAt) ?? Date()
            worldConversations[i].timeAgo = "now"
        }
        if worldTypingConversationID == dto.conversationId { worldTypingConversationID = nil }
        if selectedWorldConversationID == dto.conversationId, !mine {
            Task { try? await MessagingStore.shared.markRead(dto.conversationId, lastMessageId: mapped.id) }
        }
    }

    private func applyIncomingReaction(_ event: WorldSocketEvent) {
        guard let convoId = event.conversationId, let msgId = event.messageId,
              let userId = event.userId,
              let i = worldConversations.firstIndex(where: { $0.id == convoId }),
              let j = worldConversations[i].messages.firstIndex(where: { $0.id == msgId }) else { return }
        let mine = userId == SocialStore.shared.myProfileId
        withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
            worldConversations[i].messages[j].reactions.removeAll { $0.fromUser == mine }
            if let raw = event.tapback, let tapback = WorldTapback(rawValue: raw) {
                worldConversations[i].messages[j].reactions.append(
                    WorldReaction(tapback: tapback, fromUser: mine))
            }
        }
    }

    private func applyPollUpdate(_ dto: MessageDTO) {
        guard let i = worldConversations.firstIndex(where: { $0.id == dto.conversationId }),
              let j = worldConversations[i].messages.firstIndex(where: { $0.id == dto.id }) else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            worldConversations[i].messages[j] = MessagingStore.shared.map(dto)
        }
    }

    private func applyReadReceipt(_ event: WorldSocketEvent) {
        guard let convoId = event.conversationId,
              let i = worldConversations.firstIndex(where: { $0.id == convoId }) else { return }
        if let last = worldConversations[i].messages.lastIndex(where: { $0.fromUser }) {
            worldConversations[i].messages[last].readLabel = "Read"
        }
    }

    private func applyTyping(_ event: WorldSocketEvent) {
        guard let convoId = event.conversationId else { return }
        worldTypingConversationID = convoId
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if worldTypingConversationID == convoId { worldTypingConversationID = nil }
        }
    }

    private func wireKind(_ kind: WorldMessageKind) -> String {
        switch kind {
        case .text: return "text"
        case .emoji: return "emoji"
        case .file: return "file"
        case .photo: return "photo"
        case .video: return "video"
        case .carousel: return "carousel"
        case .audio: return "audio"
        case .location: return "location"
        case .poll: return "poll"
        case .system: return "system"
        case .timestamp: return "timestamp"
        }
    }
}
