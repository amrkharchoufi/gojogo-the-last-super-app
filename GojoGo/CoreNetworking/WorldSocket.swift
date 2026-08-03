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
            do {
                let credential = try await handshakeCredential()
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
                startPinging(socket)
                isConnected = true
                if attempt > 0 { onReconnect?() }
                attempt = 0
                try await receiveLoop(socket)
            } catch {
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

    /// A fresh connect ticket, falling back to the ID token if the backend has
    /// no ticket endpoint yet.
    ///
    /// The fallback is for one situation only: an app build newer than the
    /// deployed backend. Losing real-time chat because a rollout landed in the
    /// wrong order would be a worse failure than the log exposure the ticket
    /// removes, and the server-side switch (`WS_ALLOW_TOKEN_AUTH=false`) is what
    /// closes this path for good once both sides have shipped.
    private func handshakeCredential() async throws -> String {
        do {
            let ticket: SocketTicket = try await APIClient.shared.post("/v1/messaging/socket/ticket")
            return ticket.ticket
        } catch {
            #if DEBUG
            print("WorldSocket ticket unavailable, falling back to ID token: \(error)")
            #endif
            return try await AuthSession.shared.validIdToken()
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
                let alive: Bool = await withCheckedContinuation { cont in
                    socket.sendPing { error in cont.resume(returning: error == nil) }
                }
                if !alive {
                    socket.cancel(with: .abnormalClosure, reason: nil)
                    self?.isConnected = false
                    return
                }
            }
        }
    }
}
