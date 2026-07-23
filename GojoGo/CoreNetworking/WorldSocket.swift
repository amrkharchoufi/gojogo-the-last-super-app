import Foundation

/// My World real-time channel: a `URLSessionWebSocketTask` to the API Gateway
/// WebSocket API, authenticated with the Cognito ID token in the query string
/// (validated by the $connect authorizer Lambda). Server->client only — the
/// client sends over REST and receives message/reaction/read/typing events
/// here. Reconnects with a fixed backoff while `shouldRun` is set.
final class WorldSocket: NSObject {

    static let shared = WorldSocket()

    /// Delivered on the main actor.
    var onEvent: ((WorldSocketEvent) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var shouldRun = false
    private let decoder = JSONDecoder()

    func connect() {
        guard !shouldRun else { return }
        shouldRun = true
        Task { await openAndListen() }
    }

    func disconnect() {
        shouldRun = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func openAndListen() async {
        while shouldRun {
            do {
                let token = try await AuthSession.shared.validIdToken()
                guard var comps = URLComponents(string: BackendConfig.messagingSocketURL) else { return }
                comps.queryItems = [URLQueryItem(name: "token", value: token)]
                guard let url = comps.url else { return }

                let socket = URLSession.shared.webSocketTask(with: url)
                task = socket
                socket.resume()
                try await receiveLoop(socket)
            } catch {
                #if DEBUG
                print("WorldSocket dropped: \(error.localizedDescription)")
                #endif
            }
            guard shouldRun else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000) // backoff before reconnect
        }
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async throws {
        while shouldRun {
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
            await MainActor.run { self.onEvent?(event) }
        }
    }
}
