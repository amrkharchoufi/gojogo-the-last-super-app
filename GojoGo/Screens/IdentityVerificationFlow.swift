import Foundation
import UIKit
import IdensicMobileSDK

/// Runs Sumsub's verification flow and tells the caller when it's over.
///
/// The SDK is UIKit and presents itself modally, so this is the one place in the
/// app that reaches for a `UIViewController` — everything above it stays SwiftUI
/// and just awaits a result.
///
/// **Nothing sensitive passes through here.** The documents and the selfie go
/// from the camera straight to Sumsub; this app only ever holds a short-lived
/// launch token. That is the reason for using a vendor SDK rather than
/// collecting photos ourselves, and it's worth not quietly undoing later.
@MainActor
final class IdentityVerificationFlow {

    static let shared = IdentityVerificationFlow()

    /// The SDK deallocates itself out from under the flow if nothing holds it.
    private var sdk: SNSMobileSDK?
    private var isRunning = false

    private init() {}

    /// Presents the flow and suspends until the user closes it.
    ///
    /// - Returns: nil when the flow ran and was dismissed normally — including
    ///   when the person backed out half way, which is not an error — or a
    ///   message worth showing them when it couldn't run at all.
    ///
    /// The verdict is deliberately *not* returned. The SDK's own status is a
    /// client-side impression of a decision the server owns, and trusting it
    /// would mean the app could believe someone is verified when the backend
    /// doesn't. The caller refreshes from our API instead.
    @discardableResult
    func start() async -> String? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false }

        let token: String
        do {
            token = try await KycStore.shared.accessToken()
        } catch {
            return Self.message(from: error,
                                fallback: "Couldn't start identity verification.")
        }

        guard let presenter = Self.topViewController() else {
            return "Couldn't open identity verification."
        }

        let sdk = SNSMobileSDK(accessToken: token)
        guard sdk.isReady else {
            #if DEBUG
            print("Sumsub init failed: \(sdk.verboseStatus)")
            #endif
            return "Identity verification isn't available right now."
        }
        self.sdk = sdk

        // The SDK asks for a fresh token when the one it has expires, which it
        // will: they're minted short-lived on purpose. Without this handler a
        // slow verification simply dies part-way through.
        sdk.tokenExpirationHandler { onComplete in
            Task { @MainActor in
                onComplete(try? await KycStore.shared.accessToken())
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // `onDidDismiss` fires exactly once, for every way out — finished,
            // cancelled, or swiped away — which is what makes it safe to resume
            // a continuation from.
            sdk.onDidDismiss { [weak self] _ in
                self?.sdk = nil
                continuation.resume()
            }
            sdk.present(from: presenter)
        }
        return nil
    }

    // MARK: Presentation

    /// The controller currently on screen. Walks past whatever the app already
    /// has presented — the partner flow is itself a sheet, so presenting from
    /// the root would silently do nothing.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return nil
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private static func message(from error: Error, fallback: String) -> String {
        if case let APIClient.APIError.http(_, message) = error,
           let message, !message.trimmed.isEmpty {
            return message
        }
        return fallback
    }
}
