import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Errors surfaced by the Google/Apple sign-in flows. `.cancelled` is expected
/// (the user dismissed the sheet) and should not produce error UI.
enum SocialAuthError: Error, Equatable {
    case cancelled
    case cannotPresent
    case missingToken
}

// MARK: - Google (Cognito Hosted UI, authorization-code + PKCE)

/// Drives the Google sign-in via Cognito's Hosted UI in an
/// ASWebAuthenticationSession, then exchanges the code for Cognito tokens.
@MainActor
final class GoogleSignInClient: NSObject, ASWebAuthenticationPresentationContextProviding {

    func signIn() async throws -> CognitoAuthClient.Tokens {
        let verifier = PKCE.codeVerifier()
        let challenge = PKCE.codeChallenge(for: verifier)

        var comps = URLComponents(
            url: BackendConfig.hostedUIBaseURL.appendingPathComponent("oauth2/authorize"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: BackendConfig.cognitoClientId),
            URLQueryItem(name: "redirect_uri", value: BackendConfig.oauthRedirectURI),
            URLQueryItem(name: "identity_provider", value: "Google"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let authURL = comps.url else { throw SocialAuthError.cannotPresent }

        let callback = try await authenticate(url: authURL)
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw SocialAuthError.missingToken }

        return try await CognitoAuthClient().exchangeAuthorizationCode(
            code, codeVerifier: verifier, redirectURI: BackendConfig.oauthRedirectURI)
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: BackendConfig.oauthCallbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: SocialAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? SocialAuthError.cannotPresent)
                }
            }
            session.presentationContextProvider = self
            // Reuse the system session cookie so returning users skip re-consent.
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: SocialAuthError.cannotPresent)
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { PresentationAnchor.keyWindow() }
    }
}

// MARK: - Apple (native ASAuthorizationController)

/// Runs the native Sign in with Apple flow and returns Apple's credential plus
/// the raw nonce, which the backend needs to validate the identity token.
@MainActor
final class AppleSignInClient: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    struct Result {
        var credential: ASAuthorizationAppleIDCredential
        var rawNonce: String
    }

    private var continuation: CheckedContinuation<Result, Error>?
    private var rawNonce: String?

    func signIn() async throws -> Result {
        let nonce = PKCE.randomString()
        rawNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        // Apple echoes this value in the token's `nonce`; the backend compares it
        // to SHA-256(rawNonce), so we hash here and send the raw value onward.
        request.nonce = PKCE.sha256Hex(nonce)

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        MainActor.assumeIsolated {
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = rawNonce else {
                continuation?.resume(throwing: SocialAuthError.missingToken)
                continuation = nil
                return
            }
            continuation?.resume(returning: Result(credential: credential, rawNonce: nonce))
            continuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        MainActor.assumeIsolated {
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                continuation?.resume(throwing: SocialAuthError.cancelled)
            } else {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { PresentationAnchor.keyWindow() }
    }
}

// MARK: - Backend Apple exchange

/// Unauthenticated call to the backend's native-Apple endpoint. (APIClient can't
/// be used — it always attaches a bearer token the user doesn't have yet.)
enum BackendAuth {
    static func exchangeApple(_ body: AppleAuthBody) async throws -> CognitoAuthClient.Tokens {
        guard let url = URL(string: "/v1/auth/apple", relativeTo: BackendConfig.apiBaseURL) else {
            throw SocialAuthError.cannotPresent
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SocialAuthError.missingToken }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["message"] as? String }
            throw APIClient.APIError.http(status: http.statusCode, message: message)
        }
        let dto = try JSONDecoder().decode(AppleTokenDTO.self, from: data)
        return CognitoAuthClient.Tokens(
            idToken: dto.idToken,
            accessToken: dto.accessToken,
            refreshToken: dto.refreshToken,
            expiresIn: dto.expiresIn)
    }
}

// MARK: - Helpers

/// PKCE + nonce primitives shared by the Google and Apple flows.
enum PKCE {
    static func codeVerifier() -> String { randomString(64) }

    static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    /// URL-safe random string (also used as the raw Apple nonce).
    static func randomString(_ byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Decodes the `email` claim from a Cognito ID token (JWT) so the keychain can
/// record it after a federated sign-in. Best-effort; returns nil on any issue.
enum JWT {
    static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["email"] as? String
    }
}

private enum PresentationAnchor {
    @MainActor
    static func keyWindow() -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return window ?? ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
