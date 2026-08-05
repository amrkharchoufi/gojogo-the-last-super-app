import Foundation
import SwiftUI

// MARK: - Cold-launch cache of the GojoMessages thread list
//
// `WorldMessageArchive` already keeps the *inside* of a thread on the device.
// This keeps the outside: the rows themselves. Without it a launch had nothing
// to draw until `/v1/conversations` came back, so GojoMessages opened on a
// shimmer every single time — and on a slow connection it stayed there while
// the phone held a perfectly good copy of the same list from a minute ago.
//
// One JSON file, written whenever a server page changes the list. Same file
// protection as the archive and wiped alongside it on sign-out: a row's preview
// is the last line of somebody's message, which is plaintext with a different
// shape, not metadata.

/// Persistable mirror of `WorldConversation` — the fields the list row draws,
/// and nothing else. Messages are deliberately absent: the archive owns those,
/// and duplicating them here would mean two copies disagreeing about a thread.
private struct CachedRow: Codable {
    var id: UUID
    var contactID: UUID?
    var circleID: UUID?
    var title: String
    var preview: String
    var timeAgo: String
    var unread: Int
    var isGroup: Bool
    var pinned: Bool
    var avatarURL: String?
    var avatarGradient: [String]
    var filterBadge: String?
    var lastActivityAt: Date
    var listingContext: CachedContext?

    struct CachedContext: Codable {
        var kind: String
        var listingID: UUID?
        var title: String
        var subtitle: String?
        var imageURL: String?
    }

    init(_ c: WorldConversation) {
        id = c.id
        contactID = c.contactID
        circleID = c.circleID
        title = c.title
        preview = c.preview
        timeAgo = c.timeAgo
        unread = c.unread
        isGroup = c.isGroup
        pinned = c.pinned
        avatarURL = c.avatarURL
        avatarGradient = c.avatarGradient.map(SessionColor.hex)
        filterBadge = c.filterBadge
        lastActivityAt = c.lastActivityAt
        listingContext = c.listingContext.map {
            CachedContext(kind: $0.kind, listingID: $0.listingID, title: $0.title,
                          subtitle: $0.subtitle, imageURL: $0.imageURL)
        }
    }

    var conversation: WorldConversation {
        WorldConversation(
            id: id, contactID: contactID, circleID: circleID,
            title: title, preview: preview, timeAgo: timeAgo,
            unread: unread, isGroup: isGroup, pinned: pinned,
            avatarURL: avatarURL,
            avatarGradient: SessionColor.colors(from: avatarGradient),
            // Left empty on purpose. Opening the row loads the thread from the
            // archive, which is the copy that is actually current; seeding it
            // here would put a second, older one in front of it.
            messages: [],
            filterBadge: filterBadge,
            lastActivityAt: lastActivityAt,
            // The wallpaper is a fact about this device, and the device already
            // stores it — reading it back from `WorldPreference` is how the
            // server's refresh gets it too.
            background: WorldPreference.background(for: id) ?? .none,
            listingContext: listingContext.map {
                WorldListingContext(kind: $0.kind, listingID: $0.listingID,
                                    title: $0.title, subtitle: $0.subtitle,
                                    imageURL: $0.imageURL)
            })
    }
}

final class WorldConversationCache {
    static let shared = WorldConversationCache()

    private let fileURL: URL
    private let io = DispatchQueue(label: "app.gojogo.world-rows", qos: .utility)
    private var pending: [CachedRow]?
    private var flushScheduled = false
    private let lock = NSLock()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        // Its own directory, not the archive's. `WorldMessageArchive` exports
        // every `.json` in its folder as a thread keyed by file name, and a row
        // list is not a thread — it has no conversation id to be keyed by.
        let dir = base.appendingPathComponent("world-rows", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        fileURL = dir.appendingPathComponent("conversations.json")
    }

    /// The list as it was last seen, newest activity first. Empty on a fresh
    /// install, and after a sign-out.
    func load() -> [WorldConversation] {
        guard let data = try? Data(contentsOf: fileURL),
              let rows = try? decoder.decode([CachedRow].self, from: data)
        else { return [] }
        return rows.map(\.conversation).sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    /// Snapshots the list. Debounced like the archive: the merge runs on every
    /// poll and on every socket event, and most of those change nothing.
    func save(_ conversations: [WorldConversation]) {
        // A cap, because the file is read synchronously on the launch path and
        // nobody scrolls past the first few dozen threads before the real list
        // has landed anyway.
        let rows = conversations
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
            .prefix(80)
            .map(CachedRow.init)
        lock.lock()
        pending = Array(rows)
        let schedule = !flushScheduled
        flushScheduled = true
        lock.unlock()
        guard schedule else { return }
        io.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.flush() }
    }

    /// Sign-out, alongside `WorldMessageArchive.wipe()`.
    func wipe() {
        lock.lock()
        pending = nil
        lock.unlock()
        let url = fileURL
        io.async { try? FileManager.default.removeItem(at: url) }
    }

    private func flush() {
        lock.lock()
        let batch = pending
        pending = nil
        flushScheduled = false
        lock.unlock()
        guard let batch, let data = try? encoder.encode(batch) else { return }
        try? data.write(to: fileURL,
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
