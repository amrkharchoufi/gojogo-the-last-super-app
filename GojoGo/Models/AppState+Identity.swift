import SwiftUI
import UIKit

// MARK: - Identity verification (Sumsub)
//
// Proving who someone is used to be four fields and two checkboxes in the
// partner flow: a name, a document number, and tiles you tapped to say you had
// photographed your ID. Nothing checked any of it. This replaces that with a
// real check — Sumsub's SDK captures the document and a live face, matches them,
// and the backend's `kyc` module records the verdict.
//
// The division of labour worth remembering: the **SDK** collects, **Sumsub**
// decides, the **backend** records, and this app only ever renders. In
// particular the app never treats the SDK's own status as the answer — it asks
// our server, which is the only thing a submission is actually gated on.

extension AppState {

    // MARK: Derived state

    /// Whether the partner flow's KYC step is satisfied.
    ///
    /// Two independent halves: the person (the vendor's verdict) and the vehicle
    /// (still the local prototype until Phase 3 `dispatch`). On a backend with no
    /// vendor configured the identity half passes automatically — that
    /// environment proves identity by document upload and human review instead,
    /// and blocking the prototype behind a check that cannot run would strand it.
    var partnerKYCComplete: Bool {
        (!identity.isAvailable || identity.isVerified)
            && partnerApplication.vehicleDetailsComplete
    }

    /// Whether to draw the identity card in the partner flow at all.
    var showsIdentityVerification: Bool { backendConnected && identity.isAvailable }

    // MARK: Loading

    /// One cheap GET against our own backend — no vendor round trip. Safe to
    /// call whenever a screen that shows the status appears.
    func refreshIdentity() async {
        guard backendConnected else { return }
        do {
            identity = try await KycStore.shared.status()
        } catch {
            #if DEBUG
            print("Identity refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: The flow

    /// Launches Sumsub, then asks the server what it made of it.
    ///
    /// The pull afterwards is the important half. A verdict normally reaches us
    /// by webhook, but a webhook needs a public URL configured in Sumsub's
    /// console, and even once it is, the delivery races the user closing the
    /// sheet. Asking on dismissal means the screen behind the SDK is right by
    /// the time it's visible again.
    func startIdentityVerification() {
        guard !identityBusy, identity.canStart else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        identityBusy = true
        Task { @MainActor in
            defer { identityBusy = false }
            if let failure = await IdentityVerificationFlow.shared.start() {
                showPartnerNotice(failure)
                return
            }
            let before = identity.status
            await refreshIdentity()
            if identity.isVerified && before != .verified {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    /// Re-asks the vendor without reopening the SDK — the "check again" a person
    /// presses while a review is still pending.
    func recheckIdentity() {
        guard !identityBusy else { return }
        identityBusy = true
        Task { @MainActor in
            defer { identityBusy = false }
            do {
                identity = try await KycStore.shared.refresh()
            } catch {
                showPartnerNotice(Self.message(from: error,
                                               fallback: "Couldn't check your verification."))
            }
        }
    }

    // MARK: Notices

    /// The partner flow is a full-screen cover, so it needs its own notice —
    /// the same lesson as `merchantNotice`, where a message posted to the layer
    /// underneath simply never appeared.
    func showPartnerNotice(_ message: String) {
        partnerNoticeTask?.cancel()
        withAnimation(.ggSnappy) { partnerNotice = message }
        partnerNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.ggSnappy) { self?.partnerNotice = nil }
        }
    }

    func dismissPartnerNotice() {
        partnerNoticeTask?.cancel()
        withAnimation(.ggSnappy) { partnerNotice = nil }
    }
}
