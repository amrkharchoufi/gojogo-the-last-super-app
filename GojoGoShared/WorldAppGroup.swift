import Foundation

// MARK: - What the app and the notification extension share (E2EE Phase G)
//
// Phase G puts a second process — the Notification Service Extension — on the
// same cryptographic state the app uses. Everything that has to cross that
// boundary is named here, once, so neither side can drift from the other by
// guessing a container path or a defaults key.
//
// Three things are shared and nothing else:
//
//  - The **App Group container**, which is where the libsignal store, the
//    opened-payload vault and the ratchet lock live. The day-one rules put the
//    store there already; the vault follows here for exactly the same reason.
//  - A **shared keychain access group**, so the extension can read the device
//    identity and the auth token. Without it the extension holds files it
//    cannot decrypt and an endpoint it cannot call.
//  - A **shared UserDefaults suite** for the two small facts both processes
//    need: which profile is signed in, and whether the user wants previews.
//
// Nothing here is secret; the secrets are in the keychain and the container.
// This is the map to them.

enum WorldAppGroup {

    /// The App Group both targets declare. Registered 2026-08-04 (Phase F).
    static let identifier = "group.com.gojo.gojogo"

    /// The shared keychain access group, spelled the way the *entitlement*
    /// expands it: `$(AppIdentifierPrefix)` is the team id, and the literal has
    /// to be written out because there is no runtime substitution for it.
    ///
    /// Deliberately not the app's own `application-identifier` group: that one
    /// is `<team>.com.gojo.gojogo`, which the extension (a different bundle id)
    /// can never be granted. A third, explicitly named group is the only shape
    /// that both processes can hold.
    static let keychainAccessGroup = "T8348X4CNY.com.gojo.gojogo.shared"

    /// Where keychain items lived before the shared group existed: the app's
    /// default access group. Read-only now — `KeychainStore` migrates out of it
    /// on first launch and never writes here again.
    static let legacyKeychainAccessGroup = "T8348X4CNY.com.gojo.gojogo"

    /// The shared container, or nil if the entitlement is missing. Every caller
    /// treats nil as "carry on alone": the app falls back to its own directories
    /// and the extension simply doesn't decrypt.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Shared defaults. Falls back to `.standard` so the app keeps working
    /// unentitled — the extension has no fallback, and doesn't need one, since
    /// without the container it cannot decrypt anything anyway.
    static let defaults = UserDefaults(suiteName: identifier) ?? .standard

    // MARK: The signed-in profile
    //
    // The extension has no `SocialStore` and no session to ask. It needs the
    // local profile id for one purpose — our own end of the ratchet address —
    // and a profile id is not a secret (it is on every message on the wire).

    private static let profileIdKey = "world.e2ee.localProfileId"

    static var localProfileId: UUID? {
        get {
            guard let raw = defaults.string(forKey: profileIdKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: profileIdKey)
                return
            }
            defaults.set(newValue.uuidString, forKey: profileIdKey)
        }
    }

    // MARK: Preview preference
    //
    // The whole point of Phase G is that the *device* decides what a banner
    // says, which means the device can also decide to say nothing. Default on:
    // a user who turns previews off is making a choice, and a user who never
    // opens settings gets the feature.

    private static let previewsKey = "world.push.previews"

    static var messagePreviewsEnabled: Bool {
        get {
            guard defaults.object(forKey: previewsKey) != nil else { return true }
            return defaults.bool(forKey: previewsKey)
        }
        set { defaults.set(newValue, forKey: previewsKey) }
    }

    /// Sign-out. The profile id is what binds the shared state to an account;
    /// the preview preference is a device setting and survives deliberately.
    static func clearAccountState() {
        localProfileId = nil
    }
}
