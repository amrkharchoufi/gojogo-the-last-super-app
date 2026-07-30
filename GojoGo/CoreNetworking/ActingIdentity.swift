import Foundation

/// Who the app is publishing as right now: you, or one of your business
/// profiles (Phase 2e M1).
///
/// A business *is* a profile, so nothing about the session changes when you
/// switch — no second token, no re-auth. The switcher is pure client state and
/// the server re-checks ownership on every mutation that carries it, so the
/// worst a wrong value here can do is get a 403.
///
/// Deliberately **creation only**. Reads (feed, likes, saved) stay on the
/// person's identity, because that is whose `liked` / `bookmarked` state every
/// response is decorated with — liking as a business would show up as unliked
/// the moment the feed refreshed.
///
/// Not persisted: a relaunch comes back as yourself. Publishing as the wrong
/// identity is the expensive mistake here, so it must be a deliberate act each
/// session.
@MainActor
final class ActingIdentity {

    static let shared = ActingIdentity()

    /// nil = posting as yourself.
    var businessProfileID: UUID?

    private init() {}

    /// What the create bodies carry (`actAsProfileId`).
    var actAsProfileId: String? {
        businessProfileID?.uuidString.lowercased()
    }

    /// `?actAs=…` for the endpoints that take it as a query parameter.
    var query: String {
        actAsProfileId.map { "?actAs=\($0)" } ?? ""
    }
}
