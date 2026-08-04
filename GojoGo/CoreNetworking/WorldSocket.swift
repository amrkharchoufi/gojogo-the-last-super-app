import Foundation

/// My World real-time channel: a `URLSessionWebSocketTask` to the API Gateway
/// WebSocket API. Server->client only — the client sends over REST and receives
/// message/reaction/read/typing events here.
///
/// **Authentication is a single-use ticket, not the ID token.** A `wss://`
/// handshake cannot carry an `Authorization` header, so whatever authenticates
/// it travels in the query string — and query strings are written verbatim into
/// API Gateway and CloudWatch access logs. Putting the ID token there would
/// leave an hour of full account access sitting in plain text in a log store.
/// So the socket asks the backend for a ticket first, over an ordinary
/// authenticated request where the token rides in a header: the ticket is
/// random, bound to this account, dead in ~30 seconds, and the $connect
/// authorizer destroys it as it reads it. What reaches the log is spent.
///
/// A ticket is minted per dial, which is correct rather than wasteful — it is
/// one small request against a connection that then lives for minutes, and a
/// reused ticket would not be single-use.
///
/// The connection is treated as disposable: it is pinged every 30s so a dead
/// socket is noticed within seconds rather than on the next send, reconnects
/// with an escalating backoff, and is torn down/rebuilt when the app comes back
/// to the foreground (API Gateway drops idle sockets after 10 minutes).
/// The one-shot credential the handshake spends (`POST /v1/messaging/socket/ticket`).
private struct SocketTicket: Decodable {
    let ticket: String
    let expiresInSeconds: Int
}

@MainActor
final class WorldSocket: NSObject {

    static let shared = WorldSocket()

    /// Delivered on the main actor.
    var onEvent: ((WorldSocketEvent) -> Void)?
    /// Fires when the socket (re)connects — the app re-syncs conversations then,
    /// since anything fanned out while it was down never arrived.
    var onReconnect: (() -> Void)?
    /// Connected / not, for the "Connecting…" line in the chat header.
    var onStatusChange: ((Bool) -> Void)?

    private(set) var isConnected = false {
        didSet {
            guard isConnected != oldValue else { return }
            onStatusChange?(isConnected)
        }
    }

    private var task: URLSessionWebSocketTask?
    private var runner: Task<Void, Never>?
    private var pinger: Task<Void, Never>?
    private var shouldRun = false
    private var attempt = 0
    private let decoder = JSONDecoder()

    /// Whether this backend can still be asked for connect tickets.
    ///
    /// Starts optimistic and latches off for the rest of the session the first
    /// time a ticket is refused or cannot be minted, so a backend that predates
    /// the ticket endpoint — or an authorizer that predates ticket support —
    /// costs one failed dial rather than an unbreakable reconnect loop. A fresh
    /// launch tries tickets again.
    private var ticketsAvailable = true

    /// The socket never opened. Distinguished from an ordinary drop because it
    /// is the one failure that says something about *how* we authenticated.
    private enum SocketError: Error {
        case handshakeRefused
    }

    func connect() {
        guard !shouldRun else { return }
        shouldRun = true
        attempt = 0
        startRunner()
    }

    func disconnect() {
        shouldRun = false
        isConnected = false
        runner?.cancel(); runner = nil
        pinger?.cancel(); pinger = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    /// Drops a possibly-stale socket and dials again immediately. Called when the
    /// app returns to the foreground, where a socket that idled out looks alive
    /// until the first write fails.
    func reconnectNow() {
        guard shouldRun else { connect(); return }
        attempt = 0
        isConnected = false
        pinger?.cancel(); pinger = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        runner?.cancel()
        startRunner()
    }

    private func startRunner() {
        runner = Task { [weak self] in await self?.openAndListen() }
    }

    private func openAndListen() async {
        while shouldRun, !Task.isCancelled {
            var usedTicket = false
            do {
                let (credential, isTicket) = try await handshakeCredential()
                usedTicket = isTicket
                guard var comps = URLComponents(string: BackendConfig.messagingSocketURL) else { return }
                // Named `token` because that is the API's declared identity
                // source — API Gateway rejects a handshake missing it before the
                // authorizer runs. The value is a ticket; the authorizer tells
                // the two apart by shape.
                comps.queryItems = [URLQueryItem(name: "token", value: credential)]
                guard let url = comps.url else { return }

                let socket = URLSession.shared.webSocketTask(with: url)
                task = socket
                socket.resume()

                // Wait for the handshake to actually complete before claiming to
                // be connected. `resume()` only queues the dial: a socket the
                // authorizer refuses looks identical to a live one until the
                // first read fails, so setting `isConnected` here used to
                // announce a connection that did not exist and fire the
                // resync that follows one. A ping is the cheapest thing that
                // cannot round-trip until the socket is genuinely up.
                guard await ping(socket) else { throw SocketError.handshakeRefused }

                startPinging(socket)
                isConnected = true
                if attempt > 0 { onReconnect?() }
                attempt = 0
                try await receiveLoop(socket)
            } catch {
                // A refused handshake on a ticket means this backend cannot
                // spend one — the ticket endpoint and the $connect authorizer
                // ship separately, so a deploy can legitimately land in an order
                // where the app is minting tickets nothing will accept. Drop to
                // the ID token rather than retrying the same rejection forever;
                // the next launch tries tickets again, by which time the other
                // half is usually out.
                // `handshakeRefused` is SocketError's only case, so the type
                // test is the whole check.
                if usedTicket, error is SocketError {
                    ticketsAvailable = false
                    #if DEBUG
                    print("WorldSocket: ticket refused, falling back to ID token")
                    #endif
                }
                #if DEBUG
                print("WorldSocket dropped: \(error.localizedDescription)")
                #endif
            }
            isConnected = false
            pinger?.cancel(); pinger = nil
            guard shouldRun, !Task.isCancelled else { return }
            // 0.4s, 0.8s, 1.6s … capped at 8s — fast enough that a blip is invisible.
            attempt = min(attempt + 1, 5)
            let delay = min(0.4 * pow(2, Double(attempt - 1)), 8)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    /// A fresh connect ticket, or the ID token when this backend cannot mint one.
    ///
    /// The ticket endpoint and the `$connect` authorizer that spends tickets are
    /// deployed separately from the app, so every ordering of those three is
    /// reachable in practice. Chat going permanently silent because a rollout
    /// landed in an awkward order is a worse outcome than the log exposure the
    /// ticket removes, so the legacy path stays until the server closes it
    /// (`WS_ALLOW_TOKEN_AUTH=false`) — at which point tickets are the only thing
    /// that works and this fallback simply stops helping.
    /// - Returns: the credential, and whether it is a ticket — the caller needs
    ///   to know which one a refusal was about.
    private func handshakeCredential() async throws -> (credential: String, isTicket: Bool) {
        if ticketsAvailable {
            do {
                let ticket: SocketTicket =
                    try await APIClient.shared.post("/v1/messaging/socket/ticket")
                return (ticket.ticket, true)
            } catch {
                // No endpoint on this backend. Latch off so every later reconnect
                // skips the wasted round trip.
                ticketsAvailable = false
                #if DEBUG
                print("WorldSocket: no ticket endpoint, using ID token: \(error)")
                #endif
            }
        }
        return (try await AuthSession.shared.validIdToken(), false)
    }

    /// One ping, awaited — true if it round-tripped.
    ///
    /// Used as the "is this socket actually open" probe, because a WebSocket the
    /// server refused is indistinguishable from a healthy one until something is
    /// read from it.
    private func ping(_ socket: URLSessionWebSocketTask) async -> Bool {
        await withCheckedContinuation { cont in
            socket.sendPing { error in cont.resume(returning: error == nil) }
        }
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async throws {
        while shouldRun, !Task.isCancelled {
            let message = try await socket.receive()
            let data: Data?
            switch message {
            case .string(let text): data = text.data(using: .utf8)
            case .data(let raw): data = raw
            @unknown default: data = nil
            }
            guard let data, let event = try? decoder.decode(WorldSocketEvent.self, from: data) else {
                continue
            }
            onEvent?(event)
        }
    }

    /// Keeps the socket warm and surfaces a half-open connection quickly: a failed
    /// ping cancels the task, which unblocks `receive()` and triggers a reconnect.
    private func startPinging(_ socket: URLSessionWebSocketTask) {
        pinger?.cancel()
        pinger = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                let alive = (await self?.ping(socket)) ?? false
                if !alive {
                    socket.cancel(with: .abnormalClosure, reason: nil)
                    self?.isConnected = false
                    return
                }
            }
        }
    }
}
