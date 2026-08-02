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
    /// Three halves, which is one more than it sounds: the person (the vendor's
    /// verdict), the fields somebody types (local), and the papers they upload
    /// (the server's, because only it knows which kinds are required and which
    /// have arrived).
    ///
    /// The document half used to be three local booleans a tile toggled. Once
    /// those tiles became real uploads nothing set them again, so the Submit
    /// button was permanently grey no matter how completely the form was filled
    /// in — a checklist that could not be finished. Asking the server is also
    /// the only version of this that stays true: it is the same rule the submit
    /// endpoint enforces, rendered rather than reimplemented.
    ///
    /// On a backend with no vendor configured the identity half passes
    /// automatically — that environment proves identity by document upload and
    /// human review instead, and blocking behind a check that cannot run would
    /// strand it.
    var partnerKYCComplete: Bool {
        (!identity.isAvailable || identity.isVerified)
            && partnerApplication.vehicleDetailsComplete
            && partnerDocumentsComplete
    }

    /// Whether the papers **this screen can actually take** are on file — the
    /// same list the hint under the button names, so the two can't disagree
    /// about why it's off.
    var partnerDocumentsComplete: Bool {
        guard let application = driverApplication else { return true }
        return missingUploadLabels(application).isEmpty
    }

    /// Why the Submit button is off, in a sentence.
    ///
    /// Suppressed until the typed fields are done, because "add your number
    /// plate" is noise while somebody is still on the first field of the form.
    ///
    /// The missing uploads are named from the app's own tiles rather than from
    /// the server's blocker, and only because the server cannot yet do better:
    /// the vehicle isn't saved until the first paper is attached to it, so until
    /// then its honest answer is "add a vehicle" — a true sentence naming a
    /// button that doesn't exist on this screen. Everything else is the server's
    /// wording, which is the wording the next attempt would fail with.
    var partnerSubmitHint: String? {
        guard partnerApplication.vehicleDetailsComplete, !partnerSubmitting,
              let application = driverApplication else { return nil }
        let wanted = missingUploadLabels(application)
        if !wanted.isEmpty { return "Add a photo of your " + Self.sentenceList(wanted) + "." }
        guard let blocker = driverSubmitBlocker else { return nil }
        return blocker.prefix(1).uppercased() + String(blocker.dropFirst())
    }

    /// The papers this screen still has a tile waiting for.
    ///
    /// Scoped to those on purpose. The server's `missingDocuments` can also name
    /// kinds the driver app has no tile for — an ID card and a selfie, on a
    /// backend with no IDV vendor, which that environment collects through human
    /// review instead. Disabling the button on one of those would disable it
    /// with nothing on screen to press, so they are left to the server's own
    /// refusal, which at least says what it wants.
    ///
    /// A trottinette needs nothing here: no licence, no registration, no
    /// insurance. The server agrees — but only once it has the vehicle, which it
    /// doesn't until the first upload or the submit saves one, so the choice on
    /// screen is what this reads.
    private func missingUploadLabels(_ application: DriverApplicationDTO) -> [String] {
        guard partnerApplication.role == .driver,
              partnerApplication.driverVehicle.requiresLicense else { return [] }
        var wanted: [String] = []
        if application.needsDocument(PartnerDocumentKind.driverLicense) {
            wanted.append("driving licence")
        }
        guard application.vehicleRequired == true else { return wanted }
        // No vehicle on file yet means neither of its papers can have been
        // uploaded — attaching one is what creates it.
        let papers: [String]
        if let vehicle = application.activeVehicle {
            papers = vehicle.missingDocuments ?? []
        } else {
            papers = [VehicleDocumentKind.registration, VehicleDocumentKind.insurance]
        }
        if papers.contains(VehicleDocumentKind.registration) {
            wanted.append("vehicle registration")
        }
        if papers.contains(VehicleDocumentKind.insurance) {
            wanted.append("insurance certificate")
        }
        return wanted
    }

    /// `["a", "b", "c"]` → `"a, b and c"`.
    private static func sentenceList(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        return items.dropLast().joined(separator: ", ") + " and " + last
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
