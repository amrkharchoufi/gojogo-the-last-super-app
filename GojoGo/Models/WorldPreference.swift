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

    static var mutedConversations: Set<UUID> {
        get { Set((store.stringArray(forKey: Key.muted) ?? []).compactMap(UUID.init(uuidString:))) }
        set { store.set(newValue.map(\.uuidString), forKey: Key.muted) }
    }
}
