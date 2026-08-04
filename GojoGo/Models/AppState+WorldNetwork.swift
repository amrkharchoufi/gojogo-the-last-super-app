import SwiftUI

// MARK: - GojoMessages: the private network (Phase 2f)
//
// The half of GojoMessages that isn't chat — a phone-number graph, circles as
// the audience primitive, and content of its own. Kept apart from
// `AppState+Messaging` (conversations) on purpose: the chat detail screen is the
// finished part of this product and the re-spec explicitly leaves it alone.
//
// Nothing here ever touches `social`. A GojoMessages post is seen by the
// author's contacts or by the circles they picked and by nobody else, ever —
// the two content systems are genuinely two, and that is the point.

extension AppState {

    /// Loads the graph and the feed. Called after `connectMessaging()`, since
    /// everything here needs the phone-verified identity to exist first.
    func connectWorldNetwork() async {
        guard backendConnected, worldSetupComplete else { return }
        await loadWorldGraph()
        await refreshWorldFeed()
    }

    // MARK: Feed

    /// Placeholders instead of a blank space while the first feed fetch is in
    /// flight. Only the first: a pull-to-refresh has content on screen already,
    /// and replacing it with grey bars would read as losing it.
    ///
    /// Live from the moment the screen is, rather than from the moment the
    /// profile comes back. Waiting for `worldSetupComplete` meant the feed could
    /// not begin to shimmer until a fetch it doesn't depend on had answered, so
    /// the screen loaded in two visible stages — list first, then stories and
    /// posts, arriving after everything else had already settled. `!setupLoaded`
    /// is the honest "we don't know yet", and it is a window of one request.
    ///
    /// The same argument applies to the session itself, and it is the older half
    /// of the same bug: `backendConnected` is false for the whole of
    /// `connectBackend()`, so waiting for it meant the feed could not begin to
    /// shimmer until the session and the profile had both come back — while the
    /// messages list below it had been shimmering since the first frame. That is
    /// the two-stage load people see: chats first, then stories and posts
    /// starting a *second* loading state under a screen that looked done.
    /// `!backendResolved` is the honest "we don't know yet" for the connection.
    ///
    /// Still bounded, though: once the answer is in and there is no backend, or
    /// it is *not* set up, nobody is fetching a feed, and a placeholder for a
    /// request that will never be made is what teaches people to distrust a
    /// spinner.
    var shouldShowWorldFeedShimmer: Bool {
        !worldFeedLoaded
            && (backendConnected || !backendResolved)
            && (worldSetupComplete || !worldSetupLoaded)
            && worldStories.isEmpty && worldFeedPosts.isEmpty
    }

    func refreshWorldFeed() async {
        guard backendConnected, worldSetupComplete else { return }
        if worldFeedPosts.isEmpty && !worldFeedLoaded { worldFeedLoading = true }
        defer {
            // Same rule as the conversation refresh: don't republish AppState
            // to confirm flags that are already set.
            if worldFeedLoading { worldFeedLoading = false }
            if !worldFeedLoaded { worldFeedLoaded = true }
        }
        do {
            let (stories, posts) = try await WorldContentStore.shared.feed()
            // The 30s poll usually returns the same feed — republishing an
            // identical array re-renders every observer of AppState for nothing.
            if worldStories != stories { worldStories = stories }
            if worldFeedPosts != posts { worldFeedPosts = posts }
        } catch {
            #if DEBUG
            print("World feed failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// The author's name as *you* know them — your private rename first. The
    /// wire never carries an alias, so every name in the feed goes through here.
    func worldAuthorName(_ post: WorldPost) -> String {
        worldDisplayName(for: post.authorID, fallback: post.authorName) ?? post.authorName
    }

    func worldAuthorName(_ ring: WorldStoryRing) -> String {
        worldDisplayName(for: ring.authorID, fallback: ring.authorName) ?? ring.authorName
    }

    // MARK: Publishing

    /// Publishes a post or story. `imageData` is uploaded first so a failed
    /// upload never leaves a post with a broken image in somebody's feed.
    func publishWorldContent(kind: String, text: String, imageData: [Data],
                             audience: WorldPostAudience, circleIDs: [UUID]) async -> Bool {
        guard backendConnected, worldSetupComplete else { return false }
        do {
            var urls: [String] = []
            for data in imageData {
                if let url = try await uploadWorldImage(data) { urls.append(url) }
            }
            _ = try await WorldContentStore.shared.publish(
                kind: kind, text: text.isEmpty ? nil : text, imageURLs: urls,
                audience: audience, circleIDs: circleIDs)
            await refreshWorldFeed()
            return true
        } catch {
            #if DEBUG
            print("Publish failed: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    func deleteWorldContent(_ id: UUID) {
        // Optimistic: it's your own post, so there is no other writer to race.
        worldFeedPosts.removeAll { $0.id == id }
        Task {
            try? await WorldContentStore.shared.delete(id)
            await refreshWorldFeed()
        }
    }

    func markWorldStorySeen(_ post: WorldPost) {
        guard let ringIndex = worldStories.firstIndex(where: { $0.authorID == post.authorID }),
              let frameIndex = worldStories[ringIndex].frames.firstIndex(where: { $0.id == post.id }),
              !worldStories[ringIndex].frames[frameIndex].seen else { return }
        worldStories[ringIndex].frames[frameIndex].seen = true
        worldStories[ringIndex].allSeen = worldStories[ringIndex].frames.allSatisfy(\.seen)
        Task { try? await WorldContentStore.shared.markSeen(post.id) }
    }

    // MARK: Graph — contacts and circles

    func loadWorldGraph() async {
        guard backendConnected else { return }
        async let contacts = try? WorldContentStore.shared.contacts()
        async let circles = try? WorldContentStore.shared.circles()
        async let profile = try? WorldContentStore.shared.myProfile()
        if let contacts = await contacts {
            worldGraphContacts = contacts
            worldGraphLoaded = true
        }
        if let circles = await circles { worldCircles = circles }
        if let profile = await profile { worldRichProfile = profile }
    }

    /// Adds somebody to the graph by number, which is the only way in. Returns
    /// their profile id so the caller can open a thread with them.
    func addWorldGraphContact(phone: String) async -> UUID? {
        guard backendConnected else { return nil }
        do {
            let contact = try await WorldContentStore.shared.addContact(phone: phone)
            if !worldGraphContacts.contains(where: { $0.id == contact.id }) {
                worldGraphContacts.append(contact)
            }
            // The add hands *your* back catalogue to them, not theirs to you, so
            // your own feed doesn't change here. Refreshed anyway because the
            // add is also how a circle becomes possible and how the graph the
            // feed's names come from moves — and it's cheap. Off the caller's
            // thread of control: the tap that gets here is usually made from a
            // chat, and that screen should not wait on a feed.
            Task { await refreshWorldFeed() }
            return contact.id
        } catch {
            #if DEBUG
            print("Add contact failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Adds somebody you're already talking to — the tap behind every Add button
    /// in a thread, on either side of it. Still by number, because a number is
    /// the only way into this graph; theirs is fetched rather than typed, since
    /// the server shows it to whoever the other person reached, which is exactly
    /// the person entitled to add them.
    ///
    /// Returns false when the server won't hand the number over, which is its
    /// way of saying this isn't somebody you may add.
    func addWorldGraphContact(profileId contactId: UUID) async -> Bool {
        guard backendConnected else { return false }
        guard let profile = try? await WorldContentStore.shared.contactProfile(contactId),
              let phone = profile.phone, !phone.isEmpty else { return false }
        return await addWorldGraphContact(phone: phone) != nil
    }

    func removeWorldGraphContact(_ contactId: UUID) {
        worldGraphContacts.removeAll { $0.id == contactId }
        // Dropping a contact drops them out of every circle server-side, so the
        // local copy has to follow or a stale circle would offer them as an
        // audience that no longer resolves.
        for i in worldCircles.indices {
            worldCircles[i].memberIDs.removeAll { $0 == contactId }
        }
        Task {
            try? await WorldContentStore.shared.removeContact(contactId)
            await loadWorldGraph()
        }
    }

    @discardableResult
    func saveWorldCircle(id: UUID?, name: String, colorHex: String,
                         members: [UUID]) async -> Bool {
        guard backendConnected else { return false }
        do {
            let saved: WorldCircle
            if let id {
                saved = try await WorldContentStore.shared.updateCircle(
                    id, name: name, colorHex: colorHex, members: members)
            } else {
                saved = try await WorldContentStore.shared.createCircle(
                    name: name, colorHex: colorHex, members: members)
            }
            if let i = worldCircles.firstIndex(where: { $0.id == saved.id }) {
                worldCircles[i] = saved
            } else {
                worldCircles.append(saved)
            }
            return true
        } catch {
            #if DEBUG
            print("Save circle failed: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    func deleteWorldCircle(_ id: UUID) {
        worldCircles.removeAll { $0.id == id }
        Task { try? await WorldContentStore.shared.deleteCircle(id) }
    }

    /// Contacts as the picker shows them — private renames applied, sorted by
    /// what the owner actually reads rather than by the name they were given.
    var worldContactsForPicker: [WorldGraphContact] {
        worldGraphContacts
            .map { contact in
                var copy = contact
                copy.alias = worldAliases[contact.id] ?? contact.alias
                return copy
            }
            .sorted { $0.effectiveName.localizedCaseInsensitiveCompare($1.effectiveName) == .orderedAscending }
    }

    // MARK: Rich profile

    @discardableResult
    func saveWorldRichProfile(_ profile: WorldRichProfile) async -> Bool {
        guard backendConnected else { return false }
        do {
            worldRichProfile = try await WorldContentStore.shared.updateProfile(profile)
            return true
        } catch {
            #if DEBUG
            print("Save profile failed: \(error.localizedDescription)")
            #endif
            return false
        }
    }
}
