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
        WorldSocket.shared.onReconnect = { [weak self] in
            // Anything fanned out while the socket was down never arrived —
            // pull the list (and the open thread) back into sync.
            self?.resyncWorld()
        }
        WorldSocket.shared.onStatusChange = { [weak self] connected in
            withAnimation(.ggSnappy) { self?.worldRealtimeConnected = connected }
        }
        await loadWorldProfile()
        // Before the conversation fetch: the mapping lens reads these, so loading
        // them second would render the list once with real names.
        await loadWorldAliases()

        // Show shimmer on My World until this first list lands — otherwise the
        // empty state flashes while connectBackend is still mid-flight.
        let showLoading = worldConversations.isEmpty
        if showLoading { worldConversationsLoading = true }
        defer {
            worldConversationsLoading = false
            worldConversationsLoaded = true
        }

        do {
            let live = try await MessagingStore.shared.fetchConversations()
            mergeLiveConversations(live)
            WorldSocket.shared.connect()
            worldRealtimeConnected = WorldSocket.shared.isConnected
            // The private network on top of chat: graph, circles, feed.
            await connectWorldNetwork()
        } catch {
            #if DEBUG
            print("Messaging connect failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Re-dials the socket and refreshes what's on screen. Called when the app
    /// returns to the foreground and after a dropped connection — API Gateway
    /// closes idle sockets, so a backgrounded app always comes back stale.
    func worldEnterForeground() {
        guard backendConnected, worldSetupComplete else { return }
        WorldSocket.shared.reconnectNow()
        resyncWorld()
    }

    /// Refreshes the conversation list, plus the messages of the open thread.
    func resyncWorld() {
        Task {
            await refreshWorldConversations()
            if let id = selectedWorldConversationID { await reloadLiveConversation(id) }
        }
    }

    func refreshWorldConversations() async {
        guard backendConnected else {
            // Don't clear the shimmer here — connectBackend owns the first-load
            // lifecycle. Returning early used to flash empty before the connect.
            return
        }
        let showLoading = worldConversations.isEmpty && !worldConversationsLoaded
        if showLoading {
            worldConversationsLoading = true
            await Task.yield()
        }
        defer {
            worldConversationsLoading = false
            worldConversationsLoaded = true
        }
        do {
            let live = try await MessagingStore.shared.fetchConversations()
            mergeLiveConversations(live)
        } catch {
            #if DEBUG
            print("Conversation refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: GojoMessages contact aliases (private per-viewer renames)

    /// Pulls this account's renames and hands them to the store before the first
    /// conversation fetch, so the list never renders once with real names and
    /// again with renames a moment later.
    func loadWorldAliases() async {
        guard backendConnected else { return }
        do {
            let rows = try await MessagingStore.shared.aliases()
            var map: [UUID: String] = [:]
            for row in rows {
                guard let alias = row.alias, !alias.isEmpty else { continue }
                map[row.contactId] = alias
            }
            worldAliases = map
            MessagingStore.shared.aliasByContact = map
        } catch {
            #if DEBUG
            print("Alias load failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Renames a contact for this account only. Passing nil or a blank name
    /// clears the rename and the contact goes back to the name they set.
    ///
    /// Applied optimistically: an alias is the caller's own data with no other
    /// writer, so there is nothing to reconcile against — on failure it simply
    /// goes back to what it was.
    func renameWorldContact(_ contactId: UUID, to newName: String?) async {
        let trimmed = newName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let alias = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let previous = worldAliases[contactId]
        applyWorldAlias(alias, to: contactId)
        guard backendConnected else { return }
        do {
            _ = try await MessagingStore.shared.setAlias(contactId, to: alias)
        } catch {
            applyWorldAlias(previous, to: contactId)
            #if DEBUG
            print("Rename failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// The name this account knows someone by, for surfaces that hold an id
    /// rather than a mapped model (the contact page, a group roster).
    func worldDisplayName(for contactId: UUID?, fallback: String?) -> String? {
        MessagingStore.shared.aliasedName(for: contactId, fallback: fallback)
    }

    private func applyWorldAlias(_ alias: String?, to contactId: UUID) {
        if let alias {
            worldAliases[contactId] = alias
        } else {
            worldAliases.removeValue(forKey: contactId)
        }
        MessagingStore.shared.aliasByContact = worldAliases
        relabelWorldConversations()
    }

    /// Re-titles the 1:1 threads already on screen. The mapping lens only runs
    /// when a DTO arrives, so without this a rename wouldn't show in the list
    /// until the next fetch.
    private func relabelWorldConversations() {
        let store = MessagingStore.shared
        for i in worldConversations.indices where !worldConversations[i].isGroup {
            let parts = store.participants(in: worldConversations[i].id)
            guard let other = parts.first(where: { $0.id != store.myProfileId }) else { continue }
            if let name = store.aliasedName(for: other.id, fallback: other.displayName) {
                worldConversations[i].title = name
            }
        }
    }

    // MARK: GojoMessages setup (phone-verified identity)

    /// True once the backend has answered and the caller hasn't finished setup.
    /// Only gates when connected — offline falls back to the local demo.
    var needsWorldSetup: Bool {
        backendConnected && worldSetupLoaded && !worldSetupComplete
    }

    /// Shimmer until the first conversation fetch finishes — never flash empty first.
    var shouldShowWorldConversationShimmer: Bool {
        worldFilteredConversations.isEmpty && !worldConversationsLoaded
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
            worldSetupError = "Pick a name for GojoMessages."
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
                    // Someone who tapped "Message seller" before setting up lands
                    // in that thread now rather than on the Messages list.
                    resumePendingSellerConversation()
                }
            } catch {
                worldSetupError = (error as? APIClient.APIError)?.errorDescription
                    ?? "Couldn't save your profile. Try again."
            }
        }
    }

    /// Resolves several phone numbers to real accounts and opens a live group
    /// conversation. Returns false unless at least two others resolve.
    ///
    /// Numbers only: GojoMessages has no username lookup, so an entry that isn't
    /// a phone number can't reach anybody and is skipped.
    func startLiveGroup(recipients: [String]) async -> Bool {
        guard backendConnected else { return false }
        var ids: [UUID] = []
        var names: [String] = []
        for entry in recipients {
            guard entry.allSatisfy({ "+0123456789 -()".contains($0) }) else { continue }
            if let u = try? await MessagingStore.shared.worldByPhone(entry),
               u.profileId != SocialStore.shared.myProfileId, !ids.contains(u.profileId) {
                ids.append(u.profileId)
                names.append(worldDisplayName(for: u.profileId, fallback: u.displayName) ?? "Member")
            }
        }
        guard ids.count >= 2 else { return false }
        let title = names.prefix(3).joined(separator: ", ")
        do {
            let convo = try await MessagingStore.shared.createConversation(
                participantIds: ids, title: title, background: worldDefaultBackground)
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
    ///
    /// Also puts them in the contacts graph: reaching somebody by number *is*
    /// adding them, and the graph is what audiences resolve against — a thread
    /// with somebody who isn't a contact would leave them unable to see anything
    /// you post.
    func startLiveConversation(phone raw: String) async -> Bool {
        guard backendConnected,
              let user = try? await MessagingStore.shared.worldByPhone(raw),
              user.profileId != SocialStore.shared.myProfileId else { return false }
        _ = await addWorldGraphContact(phone: raw)
        do {
            // No title: a 1:1 is named after the other participant, and each side
            // resolves that for itself. Sending one would store *this* viewer's
            // idea of the name on a row both sides read, and the other person
            // would open the thread to find their own name on it.
            let convo = try await MessagingStore.shared.createConversation(
                participantIds: [user.profileId], title: nil,
                background: worldDefaultBackground)
            if worldConversations.firstIndex(where: { $0.id == convo.id }) == nil {
                worldConversations.insert(convo, at: 0)
            }
            openWorldConversation(convo.id)
            return true
        } catch {
            return false
        }
    }

    // MARK: A thread the server opened for a job (Phase 4 M2)

    /// Lands in the 1:1 a *vertical* opened — an order's courier↔customer
    /// thread — and does it exactly the way "Message seller" already does,
    /// because there is one way into a conversation in this app and a second
    /// one would drift.
    ///
    /// Three things it must do and one it must not. It pulls the conversation
    /// list first, since the thread was opened server-side at assignment and
    /// may never have been in this device's list. It parks behind the My World
    /// setup gate rather than opening nothing, so an unverified phone finishes
    /// verifying and *then* lands where it was going. And it leaves whatever
    /// full-screen cover was up, via that cover's own close, so nothing is left
    /// presenting over the thread. What it must not do is post anything: the
    /// courier and the customer are two people who have not spoken yet, and an
    /// opener written by the app is a message somebody has to answer.
    func openJobConversation(_ id: UUID) {
        Task {
            await refreshWorldConversations()
            enterMyWorld()
            guard !needsWorldSetup else {
                pendingSellerConversation = (id, "")
                return
            }
            openWorldConversation(id)
        }
    }

    /// Live threads become the source of truth for the Messages list; SampleData
    /// threads (no server id) stay below so the demo/composer still works.
    ///
    /// Merges *field by field* rather than replacing the array: a refresh that
    /// swapped in the server's row wholesale would drop the loaded `messages`
    /// of whatever thread is open, blanking the chat mid-conversation.
    private func mergeLiveConversations(_ live: [WorldConversation]) {
        guard !live.isEmpty else { return }
        var merged: [WorldConversation] = []
        merged.reserveCapacity(worldConversations.count + live.count)

        for var incoming in live {
            if let existing = worldConversations.first(where: { $0.id == incoming.id }) {
                incoming.messages = existing.messages
                incoming.contactID = existing.contactID
                // A local send that hasn't been echoed yet is newer than the row.
                if existing.lastActivityAt > incoming.lastActivityAt {
                    incoming.lastActivityAt = existing.lastActivityAt
                    incoming.preview = existing.preview
                }
            }
            merged.append(incoming)
        }
        let liveIds = Set(live.map(\.id))
        merged.append(contentsOf: worldConversations.filter { !liveIds.contains($0.id) })

        withAnimation(.easeOut(duration: 0.22)) { worldConversations = merged }
    }

    /// Fetches messages for a live thread the first time it's opened, then marks
    /// it read on the server. No-op for SampleData threads.
    func loadLiveConversationIfNeeded(_ id: UUID) {
        guard MessagingStore.shared.isLive(id) else { return }
        Task { await reloadLiveConversation(id) }
    }

    /// Pulls the newest page for a thread and reconciles it with what's on screen,
    /// keeping optimistic bubbles and local media (recorded audio, staged photos)
    /// that the server copy can't carry.
    func reloadLiveConversation(_ id: UUID) async {
        guard MessagingStore.shared.isLive(id) else { return }
        do {
            let page = try await MessagingStore.shared.fetchMessages(id)
            guard let i = worldConversations.firstIndex(where: { $0.id == id }) else { return }
            let localByID = Dictionary(
                worldConversations[i].messages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let serverIds = Set(page.messages.map(\.id))
            let reconciled = page.messages.map { server -> WorldMessage in
                guard let local = localByID[server.id] else { return server }
                return merging(server: server, local: local)
            }
            // Optimistic sends the server hasn't echoed back yet stay at the end.
            let pendingLocal = worldConversations[i].messages.filter {
                !serverIds.contains($0.id) && $0.fromUser && $0.kind != .timestamp
            }
            var next = reconciled + pendingLocal
            // Persisted "Read" high-water mark: the receipt survives a reload even
            // if we were offline when the peer read it (the live event only fires
            // for connected senders).
            applyReadCutoff(page.peerReadMessageId, to: &next)
            if !messagesEqual(worldConversations[i].messages, next) {
                worldConversations[i].messages = next
            }
            if let last = next.last(where: { $0.kind != .timestamp && $0.kind != .system }) {
                try? await MessagingStore.shared.markRead(id, lastMessageId: last.id)
            }
        } catch {
            #if DEBUG
            print("Live message load failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Server copy wins on everything the server owns; on-device media the wire
    /// can't carry (staged image bytes, the local recording) is carried over.
    private func merging(server: WorldMessage, local: WorldMessage) -> WorldMessage {
        var merged = server
        if merged.imageData == nil { merged.imageData = local.imageData }
        if merged.localAudioURL == nil { merged.localAudioURL = local.localAudioURL }
        if merged.carouselItems.isEmpty { merged.carouselItems = local.carouselItems }
        // Read state is client-side only — the server copy always defaults our own
        // messages to "Delivered". Carry over a "Read" the peer already acked so a
        // reload doesn't revert the receipt. The fetched peer cutoff re-applies it
        // on top; this covers the live-event case between fetches.
        if local.readAt != nil {
            merged.readAt = local.readAt
            merged.readLabel = local.readLabel
        }
        return merged
    }

    /// Marks our own messages up to (and including) `cutoffId` as "Read". Mirrors
    /// the live read-receipt event, but sourced from the server's persisted
    /// high-water mark so the receipt survives reloads and offline gaps.
    private func applyReadCutoff(_ cutoffId: UUID?, to messages: inout [WorldMessage]) {
        guard let cutoffId,
              let cutoff = messages.firstIndex(where: { $0.id == cutoffId }) else { return }
        let now = Date()
        for j in 0...cutoff where messages[j].fromUser {
            messages[j].readLabel = "Read"
            if messages[j].readAt == nil { messages[j].readAt = now }
        }
    }

    /// Cheap identity check so a poll that changed nothing doesn't rebuild the list.
    private func messagesEqual(_ lhs: [WorldMessage], _ rhs: [WorldMessage]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (a, b) in zip(lhs, rhs) {
            if a.id != b.id || a.text != b.text || a.readLabel != b.readLabel
                || a.reactions.count != b.reactions.count || a.poll != b.poll { return false }
        }
        return true
    }

    // MARK: Outbound (called from deliverWorldMessage for live threads)

    func liveSend(_ msg: WorldMessage, in conversationId: UUID,
                  replyToId: UUID? = nil, scheduledAt: Date? = nil) {
        Task {
            do {
                var mediaItems: [WorldMediaItemDTO]? = nil
                switch msg.kind {
                case .photo:
                    // A forwarded photo already lives on the CDN — reuse that
                    // object instead of uploading the same bytes again.
                    if let existing = msg.imageURL {
                        mediaItems = [WorldMediaItemDTO(imageUrl: existing, videoUrl: nil,
                                                        isVideo: false, durationLabel: nil)]
                    } else if let data = msg.imageData, let url = try await uploadWorldImage(data) {
                        mediaItems = [WorldMediaItemDTO(imageUrl: url, videoUrl: nil,
                                                        isVideo: false, durationLabel: nil)]
                    }
                case .video:
                    // Poster *and* the movie itself, so the other side can open it.
                    var poster = msg.imageURL
                    if poster == nil, let data = msg.imageData {
                        poster = try await uploadWorldImage(data)
                    }
                    var movie = msg.videoURL
                    if movie == nil, let local = msg.localVideoURL {
                        movie = try await uploadWorldVideo(local)
                        if let movie { adoptUploadedVideo(movie, for: msg.id, in: conversationId) }
                    }
                    if poster != nil || movie != nil {
                        mediaItems = [WorldMediaItemDTO(imageUrl: poster, videoUrl: movie,
                                                        isVideo: true, durationLabel: msg.durationLabel)]
                    }
                case .sticker:
                    // PNG keeps the alpha edge that makes a sticker a sticker.
                    if let data = msg.imageData {
                        let url = try await APIClient.shared.uploadMedia(data, contentType: "image/png")
                        mediaItems = [WorldMediaItemDTO(imageUrl: url, videoUrl: nil,
                                                        isVideo: false, durationLabel: nil)]
                    }
                case .audio:
                    // The recorded m4a rides in `videoUrl` — the media item is the
                    // wire's only file slot, and `isVideo: false` marks it audio.
                    if let local = msg.localAudioURL, let url = try await uploadWorldAudio(local) {
                        mediaItems = [WorldMediaItemDTO(imageUrl: nil, videoUrl: url,
                                                        isVideo: false,
                                                        durationLabel: msg.durationLabel)]
                        adoptUploadedAudio(url, for: msg.id, in: conversationId)
                    }
                case .location:
                    if let lat = msg.latitude, let lon = msg.longitude {
                        mediaItems = [WorldLocationPayload(latitude: lat, longitude: lon,
                                                           name: msg.text).mediaItem]
                    }
                case .carousel:
                    var items: [WorldMediaItemDTO] = []
                    for slide in msg.carouselItems {
                        var poster = slide.imageURL
                        if poster == nil, !slide.imageData.isEmpty {
                            poster = try await uploadWorldImage(slide.imageData)
                        }
                        var movie = slide.videoURL
                        if movie == nil, let local = slide.localVideoURL {
                            movie = try await uploadWorldVideo(local)
                        }
                        guard poster != nil || movie != nil else { continue }
                        items.append(WorldMediaItemDTO(imageUrl: poster, videoUrl: movie,
                                                       isVideo: slide.isVideo,
                                                       durationLabel: slide.durationLabel))
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

    /// Uploads a recorded voice note. Returns nil (rather than throwing) when the
    /// backend rejects the type, so the rest of the message still sends and the
    /// sender keeps local playback.
    private func uploadWorldAudio(_ url: URL) async throws -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try await APIClient.shared.uploadMedia(data, contentType: "audio/m4a")
        } catch {
            #if DEBUG
            print("Voice note upload failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Stamps the CDN URL onto the optimistic bubble so it survives a reload.
    private func adoptUploadedAudio(_ url: String, for messageID: UUID, in conversationId: UUID) {
        guard let i = worldConversations.firstIndex(where: { $0.id == conversationId }),
              let j = worldConversations[i].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        worldConversations[i].messages[j].audioURL = url
    }

    private func adoptUploadedVideo(_ url: String, for messageID: UUID, in conversationId: UUID) {
        guard let i = worldConversations.firstIndex(where: { $0.id == conversationId }),
              let j = worldConversations[i].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        worldConversations[i].messages[j].videoURL = url
    }

    /// Uploads a picked/captured movie. Videos are big and the upload can fail
    /// on a bad connection — returning nil keeps the message (and its poster)
    /// rather than dropping the send entirely.
    private func uploadWorldVideo(_ url: URL) async throws -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        do {
            return try await APIClient.shared.uploadMedia(
                data, contentType: ChatMediaOutbox.contentType(for: url))
        } catch {
            #if DEBUG
            print("Video upload failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    // MARK: Forwarding

    /// Sends an attachment on to another conversation. Media already on the CDN
    /// is referenced by URL rather than re-uploaded.
    func forwardWorldMedia(_ item: ChatMediaItem, to conversationID: UUID) {
        let message = WorldMessage(
            kind: item.isVideo ? .video : .photo,
            text: "",
            fromUser: true,
            readLabel: "Delivered",
            imageData: item.imageData,
            imageURL: item.imageURL,
            durationLabel: item.durationLabel,
            videoURL: item.videoURL,
            localVideoURL: item.localVideoURL)

        deliverWorldMessage(message,
                            preview: item.isVideo ? "You: 📹 Video" : "You: 📷 Photo",
                            in: conversationID)

        let title = worldConversations.first { $0.id == conversationID }?.title ?? "chat"
        showWorldNotice("Sent to \(title)")
    }

    /// Not private: the GojoMessages composer (AppState+WorldNetwork) uploads
    /// post and story images through the same path as a World avatar.
    func uploadWorldImage(_ data: Data) async throws -> String? {
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
        guard worldTypingIndicatorsEnabled,
              let id = selectedWorldConversationID, MessagingStore.shared.isLive(id),
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

    // Removed 2026-08-02 (Phase 2f): `startLiveConversation(handle:)`. GojoMessages
    // is a phone-number graph — an @handle is how the *public* network finds you,
    // and resolving one here was the one built behaviour the re-spec contradicts
    // outright. `ProfileStore.view(handle:)` stays; it's still how a public
    // profile is opened, just no longer a way to start a private thread.

    // MARK: GojoMessages settings

    /// Loads the settings screen's editable copy of the World profile.
    func openWorldSettings() {
        worldSettingsError = nil
        worldSettingsSaved = false
        worldSettingsAvatarData = nil
        let opened = worldSetupName.isEmpty ? user.name : worldSetupName
        worldSettingsName = opened
        worldSheet = .settings
        Task {
            await loadWorldProfile()
            // Adopt whatever the server says, unless the field was edited while
            // the request was in flight — otherwise the card opens looking dirty.
            if worldSettingsName == opened, !worldSetupName.isEmpty {
                worldSettingsName = worldSetupName
            }
        }
    }

    /// Saves the World display name / photo (`PUT /v1/world/me`), uploading a
    /// newly picked image first. Live conversations show this to everyone else,
    /// so a failure has to surface rather than silently keep the old name.
    func saveWorldSettingsProfile() {
        guard !worldSettingsBusy else { return }
        let name = worldSettingsName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 2 else {
            worldSettingsError = "Your name needs at least 2 characters."
            return
        }
        worldSettingsBusy = true
        worldSettingsError = nil
        worldSettingsSaved = false
        Task {
            defer { worldSettingsBusy = false }
            do {
                var avatarUrl = worldSetupAvatarURL
                if let data = worldSettingsAvatarData {
                    avatarUrl = try await uploadWorldImage(data)
                }
                let me = try await MessagingStore.shared.worldUpdateProfile(
                    displayName: name, avatarUrl: avatarUrl)
                worldSetupName = me.displayName ?? name
                worldSetupAvatarURL = me.avatarUrl
                worldSetupComplete = me.setupComplete
                worldSettingsAvatarData = nil
                withAnimation(.ggSnappy) { worldSettingsSaved = true }
            } catch {
                worldSettingsError = (error as? APIClient.APIError)?.errorDescription
                    ?? "Couldn't save. Try again."
            }
        }
    }

    /// Per-thread mute — device-local, since push fan-out has no per-thread flag.
    func toggleWorldMute(_ id: UUID) {
        if worldMutedConversations.contains(id) {
            worldMutedConversations.remove(id)
        } else {
            worldMutedConversations.insert(id)
        }
        WorldPreference.mutedConversations = worldMutedConversations
    }

    func isWorldMuted(_ id: UUID) -> Bool { worldMutedConversations.contains(id) }

    // MARK: Contact page

    /// Assembles the other side of a thread: the live participant record, their
    /// public GojoGo profile when they have a handle, and the group roster.
    func loadWorldContactProfile(for id: UUID) {
        guard let convo = worldConversations.first(where: { $0.id == id }) else { return }
        let contact = worldContacts.first { $0.id == convo.contactID }
        let participants = MessagingStore.shared.participants(in: id)
        let other = MessagingStore.shared.otherParticipant(in: id)
        let mine = SocialStore.shared.myProfileId

        var profile = WorldContactProfile(
            conversationID: id,
            name: other?.displayName ?? contact?.name ?? convo.title,
            handle: other?.handle ?? contact?.username.nilIfBlank,
            avatarURL: other?.avatarUrl ?? contact?.avatarURL ?? convo.avatarURL,
            phone: other.flatMap { MessagingStore.shared.phone(of: $0.id) }
                ?? contact?.phone.nilIfBlank,
            isGroup: convo.isGroup)
        profile.members = participants.map { p in
            WorldContactMember(id: p.id,
                               name: p.id == mine ? "You"
                                   : (p.displayName ?? p.handle.map { "@\($0)" } ?? "Member"),
                               handle: p.handle,
                               avatarURL: p.avatarUrl,
                               isYou: p.id == mine)
        }
        worldContactProfile = profile

        // Public profile (bio, counts) is a second, optional hop.
        guard let handle = profile.handle, backendConnected else { return }
        Task {
            guard let view = try? await ProfileStore.shared.view(handle: handle),
                  worldContactProfile?.conversationID == id else { return }
            worldContactProfile?.bio = view.bio
            worldContactProfile?.postCount = view.postCount
            worldContactProfile?.followerCount = view.followerCount
            if worldContactProfile?.avatarURL == nil { worldContactProfile?.avatarURL = view.avatarUrl }
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
            Task { await refreshWorldConversations() }
            return
        }
        let mapped = MessagingStore.shared.map(dto)
        let mine = dto.senderId == SocialStore.shared.myProfileId
        withAnimation(.spring(response: 0.42, dampingFraction: 0.7)) {
            if mine, let clientId = dto.clientId,
               let j = worldConversations[i].messages.firstIndex(where: { $0.id == clientId }) {
                // Echo of our own optimistic bubble — adopt the server id, but keep
                // the on-device media (staged photo bytes, the local recording) so
                // the bubble doesn't blink back to a network load.
                worldConversations[i].messages[j] = merging(
                    server: mapped, local: worldConversations[i].messages[j])
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
        let cutoff = event.lastReadMessageId
            .flatMap { id in worldConversations[i].messages.firstIndex(where: { $0.id == id }) }
            ?? worldConversations[i].messages.lastIndex(where: { $0.fromUser })
        guard let cutoff else { return }
        let now = Date()
        withAnimation(.ggSnappy) {
            for j in 0...cutoff where worldConversations[i].messages[j].fromUser {
                worldConversations[i].messages[j].readLabel = "Read"
                if worldConversations[i].messages[j].readAt == nil {
                    worldConversations[i].messages[j].readAt = now
                }
            }
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

    /// Removes the audio cache, map thumbnails and sticker recents.
    /// Returns how many bytes were freed.
    @discardableResult
    func clearWorldMediaCache() -> Int64 {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        var freed: Int64 = 0
        for folder in ["world-audio", "world-stickers"] {
            let dir = caches.appendingPathComponent(folder, isDirectory: true)
            freed += Self.directorySize(dir)
            try? fm.removeItem(at: dir)
        }
        StickerLibrary.shared.reload()
        return freed
    }

    var worldMediaCacheSize: Int64 {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ["world-audio", "world-stickers"]
            .map { Self.directorySize(caches.appendingPathComponent($0, isDirectory: true)) }
            .reduce(0, +)
    }

    private static func directorySize(_ dir: URL) -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
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
        case .sticker: return "sticker"
        case .audio: return "audio"
        case .location: return "location"
        case .poll: return "poll"
        case .system: return "system"
        case .timestamp: return "timestamp"
        }
    }
}
