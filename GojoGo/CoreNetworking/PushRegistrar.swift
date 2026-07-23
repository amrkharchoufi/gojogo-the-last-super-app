import Foundation

/// Bridges the APNs device token (captured in the AppDelegate) to the backend.
/// The token arrives asynchronously and only matters once the user is signed in,
/// so registration fires when *both* are true, whichever happens last.
final class PushRegistrar {

    static let shared = PushRegistrar()

    /// Set by AppState so an incoming/tapped push can refresh the activity feed.
    var onPushReceived: (() -> Void)?

    private let queue = DispatchQueue(label: "push.registrar")
    private var deviceToken: String?
    private var authenticated = false
    private var lastSent: String?
    private var muted = false

    /// APNs delivered a device token (hex).
    func updateToken(_ hexToken: String) {
        queue.async { self.deviceToken = hexToken; self.trySend() }
    }

    /// The user is signed in and the backend session is live.
    func markAuthenticated() {
        queue.async { self.authenticated = true; self.trySend() }
    }

    /// Sign-out — stop re-registering until the next login.
    func reset() {
        queue.async { self.authenticated = false; self.lastSent = nil }
    }

    /// Notifications toggle: muting drops this device from the backend's push
    /// fan-out (rather than pretending locally), unmuting re-registers it.
    func setMuted(_ muted: Bool) {
        queue.async {
            guard self.muted != muted else { return }
            self.muted = muted
            if muted {
                guard let token = self.deviceToken else { return }
                self.lastSent = nil
                Task { @MainActor in
                    try? await NotificationStore.shared.unregisterDevice(token)
                }
            } else {
                self.trySend()
            }
        }
    }

    private func trySend() {
        guard !muted, authenticated, let token = deviceToken, token != lastSent else { return }
        lastSent = token
        Task { @MainActor in
            do {
                try await NotificationStore.shared.registerDevice(token)
            } catch {
                // Retry on the next token update / next launch.
                self.queue.async { self.lastSent = nil }
                #if DEBUG
                print("Push register failed: \(error.localizedDescription)")
                #endif
            }
        }
    }
}
