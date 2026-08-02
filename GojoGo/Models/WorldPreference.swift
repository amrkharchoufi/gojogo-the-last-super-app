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
}
