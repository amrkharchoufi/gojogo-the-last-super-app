import UserNotifications
import Foundation

// MARK: - Notification Service Extension (E2EE Phase G — see E2EE-PLAN.md)
//
// Since Phase A the server has been unable to write a message into a push. It
// stores `cipherBody` and nothing it can read, so the banner it sends says
// "New message" and stops there. That was the correct trade and it was always
// meant to be temporary: this extension is the part that gets the content back,
// by decrypting it **on the device**, the way Signal does.
//
// What arrives here is the same envelope the app would open — carried in the
// payload when it fits under APNs' 4 KB, fetched by id when it doesn't. The
// extension opens it against the same session files, rewrites the banner, and
// banks the payload so the app finds it already open.
//
// Three rules run through everything below.
//
// **Never mint anything.** No identity, no session, no prekey. The extension
// reads cryptographic state; it does not create it. `mintsIdentity = false` is
// what enforces the first one, and there is no code here that could do the
// other two — establishing a session is a network round trip against the key
// directory, which belongs in the app.
//
// **Never render a failure.** Every failure path leaves the server's generic
// text exactly as it arrived. A banner that says "couldn't be decrypted" tells
// the user something they can do nothing about, on the lock screen, at 3am.
//
// **Never decrypt twice.** The app is very likely awake and receiving the same
// message over the socket. `WorldEnvelopeOpener` runs the whole look-up →
// decrypt → bank sequence inside the cross-process ratchet lock, which is the
// only reason it is safe for two processes to hold one ratchet.

final class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?
    private var fetch: Task<Void, Never>?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler:
                                @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent)
            ?? UNMutableNotificationContent()
        bestAttempt = content

        let info = request.content.userInfo
        // An older server sends no message id and no envelope; a legacy
        // plaintext message has a body the server wrote itself. Both arrive
        // here and both leave untouched, which is why `MessagePush` refuses to
        // exist without the ids rather than guessing at them.
        guard WorldAppGroup.messagePreviewsEnabled,
              info["type"] as? String == "message",
              let push = MessagePush(info),
              let me = WorldAppGroup.localProfileId
        else {
            finish()
            return
        }

        // The extension shares the app's store and must never create what it
        // cannot find. Before first unlock the keychain is unreadable, and a
        // missing identity there would otherwise be answered by generating one.
        WorldSignalStore.shared.mintsIdentity = false

        if let payload = open(push, as: me) {
            deliver(payload, for: push, in: content)
            return
        }
        // One fetch, and only for the case it exists for: an envelope whose
        // body the server dropped because the payload would have exceeded 4 KB.
        // A decrypt that failed is not retried — the bytes would be the same
        // ones — and a message with no envelope at all is already readable in
        // the banner the server sent.
        guard push.envelopeVersion != nil, push.cipherBody == nil else {
            finish()
            return
        }
        fetch = Task { [weak self] in
            guard let fetched = await MessageFetch.envelope(for: push) else {
                self?.finish()
                return
            }
            guard let self, let payload = self.open(fetched, as: me) else {
                self?.finish()
                return
            }
            self.deliver(payload, for: fetched, in: content)
        }
    }

    /// iOS is about to give up on us. Whatever the banner says right now is
    /// what ships — which is the generic text unless a decrypt already won.
    override func serviceExtensionTimeWillExpire() {
        fetch?.cancel()
        finish()
    }

    private func finish() {
        guard let handler = contentHandler, let content = bestAttempt else { return }
        contentHandler = nil
        handler(content)
    }

    // MARK: Opening

    private func open(_ push: MessagePush, as me: UUID) -> WorldEnvelopePayload? {
        // A payload the app has already opened is served from the vault without
        // touching libsignal — the ordinary case when the app is foregrounded
        // and the socket beat the push here.
        if let banked = WorldEnvelopeOpener.bankedPayload(messageId: push.messageId,
                                                          clientId: nil,
                                                          conversationId: push.conversationId) {
            return banked
        }
        guard let version = push.envelopeVersion, let body = push.cipherBody else { return nil }
        return try? WorldEnvelopeOpener.payload(
            version: version, body: body,
            messageId: push.messageId, clientId: nil,
            conversationId: push.conversationId,
            from: push.senderId, as: me)
    }

    private func deliver(_ payload: WorldEnvelopePayload, for push: MessagePush,
                         in content: UNMutableNotificationContent) {
        guard let line = Self.line(for: payload) else {
            finish()
            return
        }
        content.body = line
        // Grouping by conversation, now that there is something to group: the
        // title is already the sender's name, resolved per recipient by the
        // server (a private rename is the one thing a device cannot rewrite
        // after the fact).
        content.threadIdentifier = push.conversationId.uuidString
        finish()
    }

    /// The banner line for an opened payload.
    ///
    /// Media says what it is rather than nothing: the attachment is encrypted
    /// and its bytes are not here, but "Photo" is the truth and is what the
    /// sender would expect the other end to see. Nil means "say nothing new",
    /// which keeps the server's generic text — used for anything this build
    /// does not recognise, since a newer build's kind is not a failure.
    static func line(for payload: WorldEnvelopePayload) -> String? {
        let text = payload.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch payload.kind {
        case "text", "emoji":
            guard let text, !text.isEmpty else { return nil }
            return text
        case "photo": return "📷 Photo"
        case "video": return "🎥 Video"
        case "carousel": return "📷 Photos"
        case "sticker": return "Sticker"
        case "audio": return "🎤 Voice message" + (payload.durationLabel.map { " · \($0)" } ?? "")
        case "location": return "📍 Location"
        case "file": return "📄 " + (payload.fileName ?? "File")
        default:
            guard let text, !text.isEmpty else { return nil }
            return text
        }
    }
}

// MARK: - What the push carries
//
// The server's message push has always carried `conversationId` (the app uses
// it to stay quiet about a thread already on screen). Phase G adds the message
// id, the sender, and the envelope itself when it fits — everything needed to
// open a message without a round trip.

struct MessagePush {
    let conversationId: UUID
    let messageId: UUID
    let senderId: UUID
    let envelopeVersion: Int?
    let cipherBody: String?

    init?(_ info: [AnyHashable: Any]) {
        guard let conversation = (info["conversationId"] as? String).flatMap({ UUID(uuidString: $0) }),
              let message = (info["messageId"] as? String).flatMap({ UUID(uuidString: $0) }),
              let sender = (info["senderId"] as? String).flatMap({ UUID(uuidString: $0) })
        else { return nil }
        conversationId = conversation
        messageId = message
        senderId = sender
        // `as? Int` alone is not enough: APNs JSON numbers arrive as NSNumber.
        envelopeVersion = (info["envelopeVersion"] as? NSNumber)?.intValue
        cipherBody = info["cipherBody"] as? String
    }

    init(_ other: MessagePush, envelopeVersion: Int?, cipherBody: String?) {
        conversationId = other.conversationId
        messageId = other.messageId
        senderId = other.senderId
        self.envelopeVersion = envelopeVersion
        self.cipherBody = cipherBody
    }
}

// MARK: - Fetching a body too large for the push
//
// APNs caps a payload at 4 KB and a first (PreKey) message runs to roughly
// 2.4 KB of base64 on its own, so most messages ride in the push and a few do
// not. Those are fetched by id, with the ID token from the shared keychain.
//
// Deliberately *not* refreshing an expired token. Refreshing writes a new token
// set, and two processes racing to refresh one refresh token is how a user gets
// signed out of an app they were only receiving a notification for. An expired
// token means the generic banner stands until the app next runs — which it will
// the moment the user taps it.
enum MessageFetch {

    static func envelope(for push: MessagePush) async -> MessagePush? {
        guard let token = validIdToken(),
              let url = URL(string: "/v1/conversations/\(push.conversationId.uuidString)"
                            + "/messages/\(push.messageId.uuidString)",
                            relativeTo: BackendConfig.apiBaseURL)
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Shorter than the extension's own budget: a request still in flight
        // when iOS gives up is worse than no request, because the generic
        // banner is delivered late instead of immediately.
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let dto = try? JSONDecoder().decode(FetchedMessage.self, from: data)
        else { return nil }
        return MessagePush(push, envelopeVersion: dto.envelopeVersion, cipherBody: dto.cipherBody)
    }

    /// Only the two fields the extension is allowed to care about. Decoding the
    /// whole `MessageDto` here would tie the extension to every future wire
    /// change for no gain — it renders one line of text.
    private struct FetchedMessage: Decodable {
        let envelopeVersion: Int?
        let cipherBody: String?
    }

    private static func validIdToken() -> String? {
        guard let token = KeychainStore.get(.idToken),
              let expiryRaw = KeychainStore.get(.tokenExpiry),
              let expiry = Double(expiryRaw),
              Date().timeIntervalSince1970 < expiry
        else { return nil }
        return token
    }
}
