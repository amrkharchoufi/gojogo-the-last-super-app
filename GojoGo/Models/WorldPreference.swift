import Foundation

/// Device-local My World preferences.
///
/// These are settings about *this* device rather than the account — muted
/// threads, whether to send typing pings, the wallpaper new chats start with —
/// so they live in `UserDefaults` instead of the synced session snapshot.
/// `AppState` mirrors each one as a `@Published` property and writes back here.
enum WorldPreference {

    private enum Key {
        static let push = "world.pushEnabled"
        static let typing = "world.typingIndicators"
        static let location = "world.locationSharing"
        static let background = "world.defaultBackground"
        static let threadBackgrounds = "world.threadBackgrounds"
        static let muted = "world.mutedConversations"
        static let dismissedContext = "world.dismissedContextCards"
        static let deletedMessages = "world.deletedMessages"
    }

    private static let store = UserDefaults.standard

    /// Defaults-on settings need the "missing means true" treatment, since an
    /// absent key reads as `false`.
    private static func flag(_ key: String, default fallback: Bool) -> Bool {
        store.object(forKey: key) as? Bool ?? fallback
    }

    static var pushEnabled: Bool {
        get { flag(Key.push, default: true) }
        set { store.set(newValue, forKey: Key.push) }
    }

    static var typingIndicators: Bool {
        get { flag(Key.typing, default: true) }
        set { store.set(newValue, forKey: Key.typing) }
    }

    static var locationSharing: Bool {
        get { flag(Key.location, default: true) }
        set { store.set(newValue, forKey: Key.location) }
    }

    static var defaultBackground: WorldChatBackground {
        get { WorldChatBackground(rawValue: store.string(forKey: Key.background) ?? "") ?? .none }
        set { store.set(newValue.rawValue, forKey: Key.background) }
    }

    /// The wallpaper chosen for one thread, on this device.
    ///
    /// Per-thread and local, like the muted set beside it. The server carries a
    /// background on the conversation itself, which both sides read — fine as
    /// the starting look of a thread, wrong as a preference, because it would
    /// let one person restyle somebody else's screen. What is stored here wins.
    static func background(for conversationID: UUID) -> WorldChatBackground? {
        guard let raw = threadBackgrounds[conversationID.uuidString] else { return nil }
        return WorldChatBackground(rawValue: raw)
    }

    static func setBackground(_ background: WorldChatBackground?, for conversationID: UUID) {
        var map = threadBackgrounds
        // A picture that is no longer anybody's wallpaper is a file nobody will
        // ever open again, so it goes when the choice does.
        if let old = map[conversationID.uuidString],
           let previous = WorldChatBackground(rawValue: old)?.photoName,
           previous != background?.photoName {
            WorldWallpaperStore.delete(previous)
        }
        map[conversationID.uuidString] = background?.rawValue
        store.set(map, forKey: Key.threadBackgrounds)
    }

    private static var threadBackgrounds: [String: String] {
        store.dictionary(forKey: Key.threadBackgrounds) as? [String: String] ?? [:]
    }

    static var mutedConversations: Set<UUID> {
        get { Set((store.stringArray(forKey: Key.muted) ?? []).compactMap(UUID.init(uuidString:))) }
        set { store.set(newValue.map(\.uuidString), forKey: Key.muted) }
    }

    /// Threads whose pinned reference card the reader has put away.
    ///
    /// Local and per-thread, for the same reason the wallpaper above is: the
    /// card is one row both participants read, so hiding it on the conversation
    /// would take it off the other person's screen too. What a buyer has
    /// finished with is not a decision to make on the seller's behalf.
    static var dismissedContextCards: Set<UUID> {
        get { Set((store.stringArray(forKey: Key.dismissedContext) ?? []).compactMap(UUID.init(uuidString:))) }
        set { store.set(newValue.map(\.uuidString), forKey: Key.dismissedContext) }
    }

    // MARK: Deleted messages
    //
    // Deleting a message is a server-side fact — it has to be, or it lasts until
    // the next page fetch — and this is only the receipt for the moment before
    // the backend has heard about it. Something has to hold the line while the
    // request is in flight, or fails, or the phone is in a tunnel: the thread
    // polls, the message is still on the page, and the bubble the user just
    // deleted comes back.
    //
    // Deliberately short-lived. An id is dropped the instant the server confirms
    // it, because from then on the message is filtered before it is ever sent —
    // so what is left here is only what hasn't been confirmed, and a set that
    // grows for the life of the install is exactly what this is not.

    /// Messages deleted in this thread that the backend may not know about yet.
    static func deletedMessages(in conversationID: UUID) -> Set<UUID> {
        Set((deletedMessageMap[conversationID.uuidString] ?? []).compactMap(UUID.init(uuidString:)))
    }

    static func markMessageDeleted(_ messageID: UUID, in conversationID: UUID) {
        var map = deletedMessageMap
        var ids = map[conversationID.uuidString] ?? []
        guard !ids.contains(messageID.uuidString) else { return }
        ids.append(messageID.uuidString)
        map[conversationID.uuidString] = ids
        store.set(map, forKey: Key.deletedMessages)
    }

    /// Called once the backend has the deletion; the local note has nothing left
    /// to do.
    static func clearMessageDeleted(_ messageID: UUID, in conversationID: UUID) {
        var map = deletedMessageMap
        guard var ids = map[conversationID.uuidString] else { return }
        ids.removeAll { $0 == messageID.uuidString }
        map[conversationID.uuidString] = ids.isEmpty ? nil : ids
        store.set(map, forKey: Key.deletedMessages)
    }

    /// Deleting the whole thread makes every note about it redundant.
    static func clearDeletedMessages(in conversationID: UUID) {
        var map = deletedMessageMap
        guard map.removeValue(forKey: conversationID.uuidString) != nil else { return }
        store.set(map, forKey: Key.deletedMessages)
    }

    private static var deletedMessageMap: [String: [String]] {
        store.dictionary(forKey: Key.deletedMessages) as? [String: [String]] ?? [:]
    }
}
