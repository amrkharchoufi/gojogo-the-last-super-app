import SwiftUI

// MARK: - Becoming a driver, for real (Phase 3 M2)
//
// The old flow was a convincing mime: "pay the stake" slept for 1.6 seconds,
// "submit" inserted a role into a local Set, and the vehicle details went
// nowhere. Every one of those steps now hits the server, and the shape of the
// journey changes with it in one important way — **submitting no longer makes
// you a driver.** It puts an application in front of a human, the same queue a
// restaurant waits in since 2b M6, and the done page says so.
//
// The order is the server's (SPECS §4): application → stake → identity →
// vehicle → submit. The stake comes before the ID check because staking is what
// pays for the check.

extension AppState {

    /// The live application for the role being onboarded, if one exists yet.
    var driverApplicationIsSubmitted: Bool { driverApplication?.status == "SUBMITTED" }

    var driverStake: PartnerStakeDTO? { driverApplication?.stake }

    /// What the server would refuse a submission with — rendered as the
    /// checklist rather than discovered one 400 at a time.
    var driverSubmitBlocker: String? { driverApplication?.submitBlocker }

    // MARK: Opening the flow

    /// Fetches the application for this role, creating the draft if there isn't
    /// one. Called when the onboarding cover opens, so the stake page has a real
    /// amount and a real balance by the time anybody reaches it.
    func loadDriverApplication(_ role: PartnerRole) async {
        guard backendConnected else { return }
        do {
            if let existing = try await DispatchStore.shared.application(kind: role.partnerKind) {
                driverApplication = existing
                return
            }
            // A name and a phone are all `partner` needs to open one. The
            // business name of a driver is the driver — this is the same
            // application object a restaurant fills in, and pretending
            // otherwise would mean a second write path.
            driverApplication = try await DispatchStore.shared.createApplication(
                kind: role.partnerKind,
                name: user.name.isEmpty ? user.handle : user.name,
                phone: worldPhone ?? "",
                city: "")
        } catch {
            showPartnerNotice(Self.message(from: error,
                fallback: "Couldn't open your application."))
        }
    }

    /// Re-reads the application, and **keeps the last good one when that fails.**
    ///
    /// The `try?` this used to be assigned `nil` on any failure, which turned a
    /// refresh that didn't answer into "you have no application": the stake page
    /// fell back to its hardcoded $30, the shortfall read as zero, and a person
    /// whose stake was already locked was shown a Lock button forever. A refresh
    /// that fails has learned nothing, and nothing is what it should overwrite.
    func refreshDriverApplication(_ role: PartnerRole) async {
        guard backendConnected else { return }
        do {
            if let fresh = try await DispatchStore.shared.application(kind: role.partnerKind) {
                driverApplication = fresh
            }
        } catch {
            #if DEBUG
            print("Driver application refresh failed: \(error)")
            #endif
        }
    }

    // MARK: The stake

    /// Locks the stake for real.
    ///
    /// A 402 is the interesting path and the reason the server returns a
    /// shortfall: an empty wallet becomes a top-up for exactly the missing
    /// amount, and the driver comes straight back to this page rather than being
    /// told no.
    func payPartnerStake() {
        guard !partnerStakeProcessing else { return }
        guard let application = driverApplication else {
            showPartnerNotice("Your application isn't open yet.")
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        partnerStakeProcessing = true
        Task {
            defer { partnerStakeProcessing = false }
            do {
                driverApplication = try await DispatchStore.shared.payStake(application.id)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.easeInOut(duration: 0.32)) { partnerStep = .kyc }
            } catch APIClient.APIError.http(let status, let message) where status == 402 {
                // The wallet is short. Offer to fill it — for the right amount,
                // which the server has already worked out.
                let shortfall = driverApplication?.stake?.shortfallMinor
                    ?? application.stake?.shortfallMinor ?? 0
                showPartnerNotice(message ?? "Your wallet is short "
                    + WalletStore.money(shortfall) + ".")
                await refreshWallet()
            } catch {
                // Everything else. The server's stake movement is
                // idempotency-keyed off the application, so "the request failed"
                // and "the money didn't move" are different statements — a
                // response this app can't read is the obvious case, and it is
                // the one that stranded people on this page. Ask what actually
                // happened before telling somebody it didn't work.
                await refreshDriverApplication(role(of: application))
                if driverStake?.isPaid == true {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.easeInOut(duration: 0.32)) { partnerStep = .kyc }
                    return
                }
                showPartnerNotice(Self.message(from: error, fallback: "Couldn't take the stake."))
            }
        }
    }

    /// The role an application belongs to, so a recovery path can re-read it.
    private func role(of application: DriverApplicationDTO) -> PartnerRole {
        PartnerRole.allCases.first { $0.partnerKind == application.kind } ?? .driver
    }

    /// Tops the wallet up by exactly what the stake is short, then retries it.
    /// One tap, because two ("go and top up, then come back") is where people
    /// leave.
    func topUpForStake() {
        guard let shortfall = driverStake?.shortfallMinor, shortfall > 0 else { return }
        Task {
            topUpWallet(amountMinor: shortfall)
        }
    }

    // MARK: The vehicle

    /// Pushes the locally-entered vehicle form to the server.
    ///
    /// Written whole on submit rather than field-by-field as they type: this is
    /// one short form on one screen, and a per-keystroke PUT would be a lot of
    /// requests for a page somebody fills in once.
    func saveDriverVehicle() async -> Bool {
        guard let application = driverApplication else { return false }
        let form = partnerApplication
        let body = SaveVehicleBody(
            category: form.driverVehicle.dispatchCategory,
            make: form.vehicleMake.trimmingCharacters(in: .whitespaces),
            model: form.vehicleModel.trimmingCharacters(in: .whitespaces),
            year: Int(form.vehicleYear.trimmingCharacters(in: .whitespaces)),
            color: form.vehicleColor.trimmingCharacters(in: .whitespaces),
            plate: form.plate.trimmingCharacters(in: .whitespaces),
            region: form.vehicleRegion.trimmingCharacters(in: .whitespaces),
            registrationExpiresOn: Self.trimmedOrNil(form.registrationExpiresOn),
            insuranceExpiresOn: Self.trimmedOrNil(form.insuranceExpiresOn),
            photoUrls: nil)
        do {
            if let existing = application.activeVehicle {
                _ = try await DispatchStore.shared.editVehicle(application.id, existing.id, body)
            } else {
                _ = try await DispatchStore.shared.addVehicle(application.id, body)
            }
            driverApplication = try await DispatchStore.shared
                .application(kind: application.kind)
            return true
        } catch {
            showPartnerNotice(Self.message(from: error, fallback: "Couldn't save your vehicle."))
            return false
        }
    }

    /// Uploads a registration or insurance certificate against the active
    /// vehicle. Private prefix — the app never gets a URL back, only a key it
    /// cannot read.
    func uploadVehicleDocument(kind: String, image: Data) async {
        guard let application = driverApplication,
              let vehicle = application.activeVehicle else {
            showPartnerNotice("Add your vehicle first.")
            return
        }
        do {
            _ = try await DispatchStore.shared.uploadVehicleDocument(
                application.id, vehicle.id, kind: kind, data: image,
                contentType: APIClient.imageContentType(for: image))
            driverApplication = try await DispatchStore.shared
                .application(kind: application.kind)
        } catch {
            showPartnerNotice(Self.message(from: error, fallback: "That upload didn't stick."))
        }
    }

    // MARK: Submitting

    /// Hands the application to a human.
    ///
    /// This is the step whose *meaning* changed: it used to make somebody a
    /// driver on the spot. Now it queues them, and until a reviewer says yes
    /// there is no dispatch registration and no work. The done page is written
    /// for that, because a screen that says "you're a driver" over an
    /// application nobody has read is a lie the app would be telling on its own
    /// behalf.
    func submitDriverApplication() {
        guard !partnerSubmitting, let role = partnerOnboardingRole else { return }
        partnerSubmitting = true
        Task {
            defer { partnerSubmitting = false }
            if role == .driver, !(await saveDriverVehicle()) { return }
            guard let application = driverApplication else { return }
            do {
                driverApplication = try await DispatchStore.shared.submit(application.id)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                // Roles are the server's answer now, not a local insert — the
                // registry is what makes somebody a driver, and it does not
                // exist until an approval creates it.
                await refreshRoles()
                withAnimation(.easeInOut(duration: 0.35)) { partnerStep = .done }
            } catch {
                showPartnerNotice(Self.message(from: error,
                    fallback: "That application couldn't be submitted."))
            }
        }
    }

    static func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Roles

    /// Who this account is allowed to be, read from the server.
    ///
    /// `partnerRoles` used to be a local Set somebody inserted into at the end
    /// of onboarding. It is now derived from `/v1/me/roles`, which reads the
    /// dispatch registry — so the app and the platform cannot disagree about
    /// whether somebody may work, and a suspension takes effect on the next
    /// refresh instead of on the next reinstall.
    func refreshRoles() async {
        guard backendConnected else { return }
        guard let roles = try? await ProfileStore.shared.roles() else { return }
        var live: Set<PartnerRole> = []
        if roles.isDriver == true { live.insert(.driver) }
        if roles.isCourier == true { live.insert(.courier) }
        partnerRoles = live
        schedulePersist()
    }
}
