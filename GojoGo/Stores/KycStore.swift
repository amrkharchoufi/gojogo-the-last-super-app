import Foundation

/// Identity verification (`kyc` module).
///
/// Three calls, and none of them carry a document: the SDK uploads straight to
/// Sumsub, so the only things crossing this app's network layer are a
/// short-lived launch token and a verdict.
@MainActor
final class KycStore {

    static let shared = KycStore()

    /// Where this person stands. Local to our backend — no vendor round trip, so
    /// it's cheap enough to call on every screen that shows the status.
    func status() async throws -> IdentityVerification {
        let dto: IdentityVerificationDTO = try await APIClient.shared.get("/v1/kyc/me")
        return Self.verification(dto)
    }

    /// A fresh token for the SDK.
    ///
    /// Called to launch the flow *and* whenever the SDK's expiration handler
    /// asks for another, so it happens more than once per verification. The
    /// server treats it as idempotent — it never resets a check in progress.
    func accessToken() async throws -> String {
        let dto: KycAccessTokenDTO = try await APIClient.shared.post("/v1/kyc/access-token")
        return dto.token
    }

    /// Asks the server to go and ask Sumsub.
    ///
    /// Called the moment the SDK closes, because that's when the answer usually
    /// changed and a webhook may not have landed — or may not be configured at
    /// all. Without this the user would stare at a stale "not started" having
    /// just finished the whole flow.
    func refresh() async throws -> IdentityVerification {
        let dto: IdentityVerificationDTO = try await APIClient.shared.post("/v1/kyc/refresh")
        return Self.verification(dto)
    }

    // MARK: Mapping

    private static func verification(_ dto: IdentityVerificationDTO) -> IdentityVerification {
        IdentityVerification(
            status: IdentityStatus(wire: dto.status),
            reason: dto.reason,
            rejectLabels: dto.rejectLabels,
            isAvailable: dto.available,
            canStart: dto.canStart,
            verifiedAt: dto.verifiedAtDate)
    }
}
