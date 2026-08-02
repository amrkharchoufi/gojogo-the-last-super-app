import SwiftUI

// MARK: - Trust & safety (Phase 2e · Milestone 5)
//
// Report, block, and leave. Three controls that share one property nothing else
// in this app has: **the person using them is having a bad time**, and every
// interaction has to be short, unambiguous, and impossible to trigger by
// accident. That is why report is a sheet with a reason list rather than a menu
// item that fires immediately, why blocking asks first, and why deleting an
// account takes two deliberate steps and a typed confirmation.
//
// The app deliberately does **not** try to predict the server. It does not hide
// content locally when you report it (a report is not a takedown, and pretending
// otherwise teaches people that reporting removes things), and it does not know
// whether somebody blocked *you* — that is unknowable by design, and a client
// that inferred it from a 404 would be reconstructing exactly what the server
// declines to say.

/// What a report sheet is currently pointed at. Carrying the display name means
/// the sheet can say "Report @amina" without a second fetch.
struct ReportTarget: Identifiable, Equatable {
    let kind: ReportTargetKind
    let id: UUID
    /// "@amina", "this post", "this listing" — whatever reads naturally after
    /// the word "Report".
    let label: String
}

extension AppState {

    // MARK: Reporting

    /// Opens the report sheet. Nothing is sent until the person picks a reason
    /// and taps Submit — a one-tap report is a report nobody means.
    func openReport(_ kind: ReportTargetKind, id: UUID, label: String) {
        reportTarget = ReportTarget(kind: kind, id: id, label: label)
        reportNotice = nil
        reportSubmitted = false
        Task { await loadReportReasons() }
    }

    func closeReport() {
        reportTarget = nil
        reportBusy = false
        reportSubmitted = false
        reportNotice = nil
    }

    /// The reason list, from the server so the app never hardcodes a list that
    /// can grow. Falls back to the shipped copy rather than showing an empty
    /// picker — a person who opened this screen is not in the mood to retry.
    func loadReportReasons() async {
        guard reportReasons.isEmpty || reportReasons == ReportReason.fallback else { return }
        do {
            reportReasons = try await SafetyStore.shared.reasons()
        } catch {
            reportReasons = ReportReason.fallback
        }
    }

    func submitReport(reason: String, note: String) async {
        guard let target = reportTarget, !reportBusy else { return }
        reportBusy = true
        defer { reportBusy = false }
        do {
            let receipt = try await SafetyStore.shared.report(
                kind: target.kind, id: target.id, reason: reason, note: note)
            reportSubmitted = true
            reportNotice = receipt.alreadyReported
                ? "You've already reported this. We're still looking at it."
                : "Thanks — someone will review this."
        } catch {
            reportNotice = message(forSafety: error)
        }
    }

    // MARK: Blocking

    /// Asks first. Blocking unfollows both ways on the server and does not put
    /// those follows back on an unblock, so it is not the kind of thing a
    /// mis-tap should be able to do.
    func confirmBlock(profileId: UUID, handle: String) {
        pendingBlock = BlockCandidate(id: profileId, handle: handle)
    }

    func block(profileId: UUID, handle: String) async {
        pendingBlock = nil
        do {
            try await SafetyStore.shared.block(profileId)
            // Everything of theirs goes now rather than at the next refresh:
            // the point of tapping Block is not to see them again.
            posts.removeAll { post in
                SocialStore.shared.authorIdByPost[post.id] == profileId
            }
            blockedAccounts.removeAll { $0.id == profileId }
            blockedAccounts.insert(
                BlockedAccount(id: profileId, handle: handle, name: handle, avatarURL: nil),
                at: 0)
            if showProfile, profileUser?.handle.caseInsensitiveCompare(handle) == .orderedSame {
                closeProfile()
            }
            safetyNotice = "@\(handle) is blocked."
            await refreshBlockedAccounts()
        } catch {
            safetyNotice = message(forSafety: error)
        }
    }

    func unblock(profileId: UUID) async {
        do {
            try await SafetyStore.shared.unblock(profileId)
            blockedAccounts.removeAll { $0.id == profileId }
            // Unblocking restores visibility, not the relationship: the server
            // does not re-follow, so neither does the app.
            safetyNotice = "Unblocked."
        } catch {
            safetyNotice = message(forSafety: error)
        }
    }

    func refreshBlockedAccounts() async {
        do {
            blockedAccounts = try await SafetyStore.shared.blocked().map(BlockedAccount.init)
        } catch {
            // A settings list that fails to load is not worth a banner over.
            #if DEBUG
            print("[safety] could not load blocks: \(error)")
            #endif
        }
    }

    // MARK: Leaving

    /// Starts the deletion, then signs out — this is the last authenticated call
    /// this account can make, because the server disables sign-in in the same
    /// request. Anything the app tried afterwards would 401.
    func deleteMyAccount() async {
        guard !deleteAccountBusy else { return }
        deleteAccountBusy = true
        defer { deleteAccountBusy = false }
        do {
            let status = try await SafetyStore.shared.deleteAccount()
            deletionStatus = status
            // A beat, so the confirmation is readable before the app returns to
            // the welcome screen.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            signOut()
        } catch {
            safetyNotice = message(forSafety: error)
        }
    }

    private func message(forSafety error: Error) -> String {
        (error as? APIClient.APIError)?.errorDescription ?? error.localizedDescription
    }
}

/// An account on your own block list. Only ever accounts *you* blocked — who
/// blocked you is not knowable, here or anywhere.
struct BlockedAccount: Identifiable, Equatable {
    let id: UUID
    var handle: String
    var name: String
    var avatarURL: String?

    init(id: UUID, handle: String, name: String, avatarURL: String?) {
        self.id = id
        self.handle = handle
        self.name = name
        self.avatarURL = avatarURL
    }

    init(_ dto: BlockedProfileDTO) {
        id = dto.id
        handle = dto.handle ?? ""
        name = dto.name
        avatarURL = dto.avatarUrl
    }
}

/// A block waiting on a confirmation.
struct BlockCandidate: Identifiable, Equatable {
    let id: UUID
    let handle: String
}

// MARK: - The safety pack (Phase 3 · Milestone 5)
//
// Emergency contacts, a public tracking link, SOS, and the passenger side of
// community vehicle verification. Three of the four are used at the worst
// moment somebody will ever have with this app, which sets the rules:
//
//   * **Nothing here guesses.** The emergency number, the link, the wording of
//     the message — all of it comes from the server, because a client that
//     composed its own would eventually compose a different one.
//   * **The dangerous control takes two taps** and the safe one takes one.
//     Sharing a trip is a tap. SOS is a tap and a confirmation, because an
//     alarm raised by accident is a person explaining themselves to their
//     mother at midnight — and one that needs three taps is an alarm nobody
//     raises in time.
//   * **The app never dials on its own.** SOS hands back a number and the
//     person taps it. A phone that starts calling emergency services by itself
//     is a phone people turn this feature off on.

extension AppState {

    // MARK: Emergency contacts

    func loadEmergencyContacts() async {
        guard backendConnected else { return }
        do {
            let response = try await SafetyStore.shared.emergencyContacts()
            emergencyContacts = response.contacts
            emergencyContactsMax = response.max
        } catch {
            safetyNotice = message(forSafety: error)
        }
    }

    func addEmergencyContact(name: String, phone: String, relationship: String) async {
        guard !emergencyContactsBusy else { return }
        emergencyContactsBusy = true
        defer { emergencyContactsBusy = false }
        do {
            let added = try await SafetyStore.shared.addEmergencyContact(
                name: name, phone: phone, relationship: relationship)
            emergencyContacts.append(added)
        } catch {
            safetyNotice = message(forSafety: error)
        }
    }

    func removeEmergencyContact(_ id: UUID) async {
        // Removed locally first: the list is short, the call is a delete, and a
        // row that lingers after a swipe reads as a failure that didn't happen.
        let previous = emergencyContacts
        emergencyContacts.removeAll { $0.id == id }
        do {
            try await SafetyStore.shared.removeEmergencyContact(id)
        } catch {
            emergencyContacts = previous
            safetyNotice = message(forSafety: error)
        }
    }

    // MARK: Sharing a trip

    /// A public link to the live trip, for somebody who isn't in the app.
    ///
    /// Returns the whole written message rather than just the URL, so the share
    /// sheet sends a sentence a recipient understands instead of a bare link
    /// from an app they may never have heard of.
    func shareTrip() async -> String? {
        guard let ride, backendConnected, !shareBusy else { return nil }
        shareBusy = true
        defer { shareBusy = false }
        do {
            let shared = try await TravelStore.shared.share(ride.id)
            tripShare = shared
            return shared.message
        } catch {
            safetyNotice = message(forSafety: error)
            return nil
        }
    }

    func stopSharingTrip() async {
        guard let ride, backendConnected else { return }
        let previous = tripShare
        tripShare = nil
        do {
            try await TravelStore.shared.stopSharing(ride.id)
        } catch {
            tripShare = previous
            safetyNotice = message(forSafety: error)
        }
    }

    // MARK: SOS

    /// Raises the alarm.
    ///
    /// The server flags the trip, mints a tracking link and pushes to every
    /// emergency contact who is also on GojoGo. What comes back is the local
    /// emergency number to dial and the contacts nobody could reach that way —
    /// which is what the SOS sheet turns into a message the person sends
    /// themselves, from their own number, which is the one their family opens.
    func raiseSos() async {
        guard let ride, backendConnected, !sosBusy else { return }
        sosBusy = true
        defer { sosBusy = false }
        do {
            sos = try await TravelStore.shared.sos(ride.id)
            // The ride row now carries the flag; refreshing keeps both sides of
            // the screen telling the same story.
            await refreshRide()
        } catch {
            safetyNotice = message(forSafety: error)
        }
    }

    /// The local emergency number, as a `tel:` URL. Nil rather than a guess when
    /// the server hasn't answered — a wrong emergency number is worse than none.
    var emergencyDialURL: URL? {
        guard let number = sos?.emergencyNumber, !number.isEmpty else { return nil }
        return URL(string: "tel://" + number.filter { $0.isNumber || $0 == "+" })
    }

    // MARK: Community vehicle verification

    /// Vehicles this account has been asked to confirm.
    ///
    /// Silent on failure, deliberately: this is a bonus somebody may earn, and
    /// an error banner about it on the travel screen would be noise at the
    /// moment they are trying to get somewhere.
    func loadVerificationInvites() async {
        guard backendConnected else { return }
        verificationInvites = (try? await SafetyStore.shared.verificationInvites()) ?? []
    }

    /// Answers all five questions. The server decides what they add up to — a
    /// badge and a reward, or a flag and a suspension — and the app never
    /// pre-empts that, because "thanks, verified!" over a rejection would be a
    /// lie the person could check.
    func answerVerification(_ invite: VerificationInviteDTO,
                            driverMatched: Bool, photosMatched: Bool, plateMatched: Bool,
                            roadworthy: Bool, noFraud: Bool, comment: String) async {
        guard !verificationBusy else { return }
        verificationBusy = true
        defer { verificationBusy = false }
        do {
            _ = try await SafetyStore.shared.answerVerification(
                invite.id, driverMatched: driverMatched, photosMatched: photosMatched,
                plateMatched: plateMatched, roadworthy: roadworthy, noFraud: noFraud,
                comment: comment)
            verificationInvites.removeAll { $0.id == invite.id }
            openVerification = nil
            let allYes = driverMatched && photosMatched && plateMatched && roadworthy && noFraud
            safetyNotice = allYes
                ? "Thanks — that vehicle is now community verified."
                : "Thanks for telling us. Somebody will look at this."
        } catch {
            safetyNotice = message(forSafety: error)
        }
    }
}

extension VerificationInviteDTO {

    /// "USD 3.00" — what the card offers, formatted once rather than in three
    /// places.
    var rewardText: String {
        String(format: "%@ %.2f", currency, Double(rewardMinor) / 100)
    }

    /// "White Dacia Logan · 12345-A-6", as much of it as was filled in.
    var carLine: String {
        vehiclePlate.isEmpty ? vehicleLabel : "\(vehicleLabel) · \(vehiclePlate)"
    }
}
