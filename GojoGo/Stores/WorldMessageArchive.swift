import Foundation

// MARK: - Local message history (E2EE Phase A — see E2EE-PLAN.md)
//
// GojoMessages history becomes local-first here. This is forced, not chosen:
// once the Double Ratchet lands (Phase C), a ciphertext decrypts exactly once
// — deleting the message key after use *is* forward secrecy — so the server's
// stored copy is a one-time delivery, not an archive. Whatever this device has
// decrypted must live on this device, or it is gone.
//
// One JSON file per conversation under Application Support, written through a
// debounce so a burst of socket traffic costs one write. Files carry
// `completeUntilFirstUserAuthentication` — the same standard as the keychain
// tokens — and are wiped on sign-out: the archive is the account's plaintext,
// and it must not outlive the account on a shared device.
//
// Media bytes are deliberately NOT persisted. A staged photo's JPEG or a
// recording's samples would bloat every write; the archive keeps the URLs and
// `ImageCache` / the audio cache keep the bytes.

/// Persistable mirror of `WorldMessage`. A separate type, not `Codable` bolted
/// onto the UI model: what survives a relaunch is a deliberate list, and
/// transient fields (staged image bytes, reaction targets) must not creep into
/// the archive just because someone added a property to the view model.
private struct ArchivedMessage: Codable {
    var id: UUID
    var kind: String
    var text: String
    var fromUser: Bool
    var fileName: String?
    var fileMeta: String?
    var readLabel: String?
    var readAt: Date?
    var imageURL: String?
    var durationLabel: String?
    var senderName: String?
    var carousel: [Slide]?
    var reactions: [Reaction]?
    var replyAuthor: String?
    var replyPreview: String?
    var replyFromUser: Bool?
    var poll: Poll?
    var scheduledLabel: String?
    var audioURL: String?
    var localAudioPath: String?
    var videoURL: String?
    var localVideoPath: String?
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date

    struct Slide: Codable {
        var imageURL: String?
        var videoURL: String?
        var isVideo: Bool
        var durationLabel: String?
    }

    struct Reaction: Codable {
        var tapback: String
        var fromUser: Bool
    }

    struct Poll: Codable {
        var question: String
        var options: [Option]
        var allowsMultiple: Bool
        struct Option: Codable {
            var id: UUID
            var text: String
            var voters: [String]
        }
    }
}

final class WorldMessageArchive {
    static let shared = WorldMessageArchive()

    private let directory: URL
    private let io = DispatchQueue(label: "app.gojogo.world-archive", qos: .utility)
    /// Conversations with unsaved changes, flushed by the debounce.
    private var pending: [UUID: [ArchivedMessage]] = [:]
    private var flushScheduled = false
    private let lock = NSLock()
    /// Decoded threads, kept for the life of the process.
    ///
    /// The disk file is the durable copy; this is what makes re-reading it free.
    /// Two callers made that matter. Re-opening a thread decoded its whole
    /// history on the main actor before it could draw — which is the "the chat
    /// loads all over again" every time you go back in. And the list's merge
    /// calls `lastPreview` for every encrypted row it can't preview itself, so
    /// the 30-second poll was reading and decoding *every* thread on the phone,
    /// on the main actor, to re-derive sentences that hadn't changed.
    private var memory: [UUID: [WorldMessage]] = [:]

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        directory = base.appendingPathComponent("world-messages", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    }

    // MARK: Reading

    /// The archived thread, oldest first. Empty when nothing was ever stored —
    /// indistinguishable from a brand-new thread on purpose.
    ///
    /// Served from memory after the first read. A thread nobody has opened this
    /// run still costs one disk read and one decode; every read after that is a
    /// dictionary lookup.
    func load(_ conversationId: UUID) -> [WorldMessage] {
        lock.lock()
        if let cached = memory[conversationId] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let url = fileURL(conversationId)
        guard let data = try? Data(contentsOf: url),
              let archived = try? decoder.decode([ArchivedMessage].self, from: data)
        else {
            // Cache the miss too. Otherwise a thread with no file on disk — a
            // brand-new one, or every row on a fresh install — pays a failed
            // file read on every poll, forever.
            lock.lock(); memory[conversationId] = []; lock.unlock()
            return []
        }
        // Builds before the placeholders were kept out (below) wrote them here
        // as ordinary text, which is what turned one bad refetch into a thread
        // of permanent "couldn't be decrypted" bubbles: the archive is the copy
        // the merge trusts, so a stored placeholder outranks every later attempt
        // at the real message forever. Dropping them on the way in is the
        // migration — there is no version to check and no content to lose.
        let messages = archived.filter { !Self.isPlaceholder($0) }.map(Self.toMessage)
        lock.lock(); memory[conversationId] = messages; lock.unlock()
        return messages
    }

    /// Whether an archived row is one of this build's "couldn't open it"
    /// sentences rather than something somebody sent.
    private static func isPlaceholder(_ a: ArchivedMessage) -> Bool {
        a.kind == WorldMessageKind.text.rawValue
            && WorldMessagePlaceholder.all.contains(a.text)
    }

    /// The list-row preview this device can derive without the server —
    /// "You: on my way" for own messages, the snippet alone for theirs.
    func lastPreview(_ conversationId: UUID) -> String? {
        guard let last = load(conversationId).last(where: {
            $0.kind != .timestamp && $0.kind != .system
        }) else { return nil }
        return last.fromUser ? "You: \(last.snippetText)" : last.snippetText
    }

    // MARK: Writing

    /// Snapshots a thread. Cheap to call from every mutation site: the encode
    /// and the disk write happen off-main after a debounce, so a socket burst
    /// costs one write, not one per message.
    func save(_ conversationId: UUID, messages: [WorldMessage]) {
        let archived = messages.compactMap(Self.toArchived)
        lock.lock()
        pending[conversationId] = archived
        // In memory it's the snapshot that was handed in, not a round trip
        // through `ArchivedMessage` — the caller's copy is the newer one, and
        // it carries the staged bytes the archived form deliberately drops.
        memory[conversationId] = messages
        let schedule = !flushScheduled
        flushScheduled = true
        lock.unlock()
        guard schedule else { return }
        io.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.flush() }
    }

    func remove(_ conversationId: UUID) {
        lock.lock()
        pending[conversationId] = nil
        memory[conversationId] = nil
        lock.unlock()
        let url = fileURL(conversationId)
        io.async { try? FileManager.default.removeItem(at: url) }
    }

    /// Sign-out: the archive is the account's plaintext and must not outlive it.
    func wipe() {
        lock.lock()
        pending = [:]
        memory = [:]
        lock.unlock()
        let dir = directory
        io.async {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
    }

    // MARK: Backup (Phase F)
    //
    // Files verbatim, not re-encoded models. The archive's on-disk shape is
    // already the thing worth keeping, and decoding to `WorldMessage` and back
    // would quietly drop any field a future build added.

    func exportFiles() -> [String: Data] {
        flush()
        var out: [String: Data] = [:]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".json") {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { continue }
            out[String(name.dropLast(5))] = data
        }
        return out
    }

    func importFiles(_ files: [String: Data]) {
        // The memory tier describes the files that were just replaced, so it is
        // now wrong about every thread in the backup.
        lock.lock(); pending = [:]; memory = [:]; lock.unlock()
        for (id, data) in files {
            try? data.write(to: directory.appendingPathComponent("\(id).json"),
                            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private func flush() {
        lock.lock()
        let batch = pending
        pending = [:]
        flushScheduled = false
        lock.unlock()
        for (id, messages) in batch {
            guard let data = try? encoder.encode(messages) else { continue }
            try? data.write(to: fileURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    // MARK: Mapping

    private static func toArchived(_ m: WorldMessage) -> ArchivedMessage? {
        // A payload this device couldn't open is never written down, for the
        // same reason `WorldEnvelopeVault` never banks a failure: some of them
        // are transient — the store is locked before first unlock, the profile
        // id hasn't loaded yet — and archiving the sentence makes a message that
        // would open a second later unreadable for good. The message isn't lost
        // by leaving it out; it is on the server, and the next pass re-derives
        // whatever it can. What is lost by keeping it is the real message.
        guard !m.isUndecryptable else { return nil }
        // Timestamps are re-derived, and a reaction overlay's lifted copy is
        // transient — but both already never enter `messages`. Everything that
        // does is worth keeping.
        return ArchivedMessage(
            id: m.id, kind: m.kind.rawValue, text: m.text, fromUser: m.fromUser,
            fileName: m.fileName, fileMeta: m.fileMeta,
            readLabel: m.readLabel, readAt: m.readAt,
            imageURL: m.imageURL, durationLabel: m.durationLabel,
            senderName: m.senderName,
            carousel: m.carouselItems.isEmpty ? nil : m.carouselItems.map {
                .init(imageURL: $0.imageURL, videoURL: $0.videoURL,
                      isVideo: $0.isVideo, durationLabel: $0.durationLabel)
            },
            reactions: m.reactions.isEmpty ? nil : m.reactions.map {
                .init(tapback: $0.tapback.rawValue, fromUser: $0.fromUser)
            },
            replyAuthor: m.replyTo?.authorName, replyPreview: m.replyTo?.preview,
            replyFromUser: m.replyTo?.fromUser,
            poll: m.poll.map {
                .init(question: $0.question,
                      options: $0.options.map { .init(id: $0.id, text: $0.text, voters: $0.voters) },
                      allowsMultiple: $0.allowsMultiple)
            },
            scheduledLabel: m.scheduledLabel,
            audioURL: m.audioURL, localAudioPath: m.localAudioURL?.path,
            videoURL: m.videoURL, localVideoPath: m.localVideoURL?.path,
            latitude: m.latitude, longitude: m.longitude,
            // The server's send time when we have it. `Date()` was always meant
            // as a placeholder, and it is the field the receipt reads back to
            // date a "Read" it has no clock for.
            createdAt: m.sentAt ?? Date())
    }

    private static func toMessage(_ a: ArchivedMessage) -> WorldMessage {
        WorldMessage(
            id: a.id,
            kind: WorldMessageKind(rawValue: a.kind) ?? .text,
            text: a.text,
            fromUser: a.fromUser,
            fileName: a.fileName, fileMeta: a.fileMeta,
            readLabel: a.readLabel, readAt: a.readAt, sentAt: a.createdAt,
            imageURL: a.imageURL,
            durationLabel: a.durationLabel,
            senderName: a.senderName,
            carouselItems: (a.carousel ?? []).map {
                WorldCarouselItem(imageData: Data(), isVideo: $0.isVideo,
                                  durationLabel: $0.durationLabel,
                                  imageURL: $0.imageURL, videoURL: $0.videoURL)
            },
            reactions: (a.reactions ?? []).map {
                WorldReaction(tapback: WorldTapback(rawValue: $0.tapback) ?? .heart,
                              fromUser: $0.fromUser)
            },
            replyTo: a.replyPreview.map {
                WorldReplySnippet(authorName: a.replyAuthor ?? "", preview: $0,
                                  fromUser: a.replyFromUser ?? false)
            },
            poll: a.poll.map {
                WorldPoll(question: $0.question,
                          options: $0.options.map {
                              WorldPollOption(id: $0.id, text: $0.text, voters: $0.voters)
                          },
                          allowsMultiple: $0.allowsMultiple)
            },
            scheduledLabel: a.scheduledLabel,
            audioURL: a.audioURL,
            localAudioURL: a.localAudioPath.map { URL(fileURLWithPath: $0) },
            videoURL: a.videoURL,
            localVideoURL: a.localVideoPath.map { URL(fileURLWithPath: $0) },
            latitude: a.latitude, longitude: a.longitude)
    }

    private func fileURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString.lowercased()).json")
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
