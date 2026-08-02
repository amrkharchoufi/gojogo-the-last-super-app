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

    /// Whether the form is still the applicant's to change. False from the
    /// moment it is submitted until a reviewer sends it back — the server
    /// refuses every write in between, so anything this app offers in that
    /// window is a button that ends in a 409.
    var driverApplicationIsOpen: Bool { driverApplication?.canEdit ?? true }

    /// Sent back to be fixed. Not a dead end and not a fresh start: the same
    /// application, keeping its documents and its stake, reopened for editing.
    var driverApplicationWasRejected: Bool { driverApplication?.status == "REJECTED" }

    /// Approved once, switched off since.
    var driverApplicationIsSuspended: Bool { driverApplication?.status == "SUSPENDED" }

    /// The reviewer's own sentence about this application, when there is one.
    ///
    /// Only ever set on a rejection or a suspension — the server clears it on
    /// resubmission and on approval, so it can't turn up as yesterday's verdict
    /// beside an application currently in the queue. Blank notes are treated as
    /// no note: a reviewer who pressed the button without typing has said
    /// nothing, and an empty bubble is worse than the app's own wording.
    var driverReviewNote: String? {
        guard let note = driverApplication?.reviewNote?
            .trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else { return nil }
        return note
    }

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
                // Somebody coming back to an application they started should
                // find their licence and their car where they left them. The
                // form is local state that `startPartnerOnboarding` blanks on
                // every entry, so without this a returning driver sees an empty
                // card over details the server already has — and re-types them.
                hydrateDriverForm(from: existing)
                await resumePartnerStep(for: existing)
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

    /// Opens the flow where the application actually is, rather than always at
    /// the first page.
    ///
    /// An application that has been submitted has no form left in it: the server
    /// closes it to edits until a reviewer sends it back, and re-entering the
    /// flow put people through the rules and the stake again only to end on a
    /// Submit button their application had already passed — an invitation to
    /// redo something nobody can redo. They see where it stands instead, which
    /// is the one true thing there is to show and the only thing left to do
    /// about it (wait).
    ///
    /// A rejection is the other direction and lands on the form: the server
    /// reopens that one, the reviewer's note says what to fix, and the fix is a
    /// re-upload. Rules they have already agreed to and a stake they have
    /// already paid would stand between a returning applicant and the sentence
    /// telling them what was wrong, so both are skipped — and the stake only
    /// where the server says it is already held, because that page is the one
    /// with something left to do if it isn't.
    private func resumePartnerStep(for application: DriverApplicationDTO) async {
        if application.canEdit {
            // A stake that isn't required counts as settled: that page has
            // nothing left on it either.
            let stakeSettled = application.stake.map { $0.isPaid || !$0.required } ?? false
            guard application.status == "REJECTED", stakeSettled else { return }
            withAnimation(.easeInOut(duration: 0.32)) { partnerStep = .kyc }
            return
        }
        // An approval that landed while the app was closed makes them a driver,
        // and the completion page reads that from the registry — so ask it
        // before showing the page rather than telling somebody they are still
        // in a queue they have already left.
        if application.status == "APPROVED" { await refreshRoles() }
        withAnimation(.easeInOut(duration: 0.32)) { partnerStep = .done }
    }

    /// Fills the local form in from what the server is already holding.
    ///
    /// Only ever called when the flow opens — a refresh mid-typing must not
    /// reach in and rewrite the field somebody is halfway through.
    private func hydrateDriverForm(from application: DriverApplicationDTO) {
        partnerApplication.licenseNumber = application.driverLicenseNumber ?? ""
        guard let vehicle = application.activeVehicle else { return }
        partnerApplication.driverVehicle =
            DriverVehicle.allCases.first { $0.dispatchCategory == vehicle.category }
            ?? partnerApplication.driverVehicle
        partnerApplication.vehicleMake = vehicle.make
        partnerApplication.vehicleModel = vehicle.model
        partnerApplication.vehicleYear = vehicle.year.map { String($0) } ?? ""
        partnerApplication.vehicleColor = vehicle.color
        partnerApplication.plate = vehicle.plate
        // Falls back to the device rather than to blank: a vehicle saved before
        // the country field existed is one the old app could only have meant
        // locally, and an empty picker is a step backwards from a good guess.
        partnerApplication.vehicleCountry = vehicle.country.flatMap {
            $0.isEmpty ? nil : $0
        } ?? partnerApplication.vehicleCountry
        partnerApplication.vehicleRegion = vehicle.region
        partnerApplication.registrationExpiresOn = vehicle.registrationExpiresOn ?? ""
        partnerApplication.insuranceExpiresOn = vehicle.insuranceExpiresOn ?? ""
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
            country: form.vehicleCountry,
            // Sent only where it is part of the plate. Everywhere else it stays
            // empty on purpose — the server scopes plate uniqueness by country
            // and subdivision, so a city typed into it would put two spellings
            // of the same town into two different scopes and let one car be
            // registered twice.
            region: VehicleRegistry.rules(for: form.vehicleCountry).asksForSubdivision
                ? form.vehicleRegion.trimmingCharacters(in: .whitespaces) : "",
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

    /// One side of the driving licence, uploaded against the *application*
    /// rather than against a car — it is a fact about the person holding it, and
    /// it stays theirs when they sell the Yaris.
    ///
    /// This tile spent a milestone as a boolean somebody tapped: it turned
    /// "Captured" on the first press, uploaded nothing, and put a tick where a
    /// reviewer expected a licence. The vehicle papers stopped doing that when
    /// `documentTile` arrived; this is the same correction for the same reason.
    func uploadDriverLicense(kind: String, image: Data) async {
        guard let application = driverApplication else {
            showPartnerNotice("Your application isn't open yet.")
            return
        }
        do {
            driverApplication = try await DispatchStore.shared.uploadApplicationDocument(
                application.id, kind: kind, data: image,
                contentType: APIClient.imageContentType(for: image))
        } catch {
            showPartnerNotice(Self.message(from: error, fallback: "That upload didn't stick."))
        }
    }

    /// Whether one side of the licence is on file — asked of the server, which
    /// is the only thing that knows, and which also decides whether a licence is
    /// needed at all (a trottinette needs none).
    func driverLicenseUploaded(_ kind: String) -> Bool {
        guard let application = driverApplication else { return false }
        return !application.needsDocument(kind)
    }

    /// Sends the number off the licence. Called before the submit rather than on
    /// every keystroke: this is one short field on a form somebody fills in once,
    /// and a PUT per character would be a lot of requests for it.
    ///
    /// It used to be sent nowhere at all — a field that looked collected, wasn't,
    /// and reached no reviewer.
    @discardableResult
    func saveDriverLicenseNumber() async -> Bool {
        guard let application = driverApplication else { return false }
        let number = partnerApplication.licenseNumber.trimmingCharacters(in: .whitespaces)
        guard number != (application.driverLicenseNumber ?? "") else { return true }
        do {
            driverApplication = try await DispatchStore.shared
                .saveDriverLicenseNumber(application.id, number)
            return true
        } catch {
            showPartnerNotice(Self.message(from: error,
                fallback: "Couldn't save your licence number."))
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
            if role == .driver {
                guard await saveDriverLicenseNumber(), await saveDriverVehicle() else { return }
            }
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
