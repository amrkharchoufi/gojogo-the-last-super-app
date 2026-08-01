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
