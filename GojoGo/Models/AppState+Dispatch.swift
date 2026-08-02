import SwiftUI
import CoreLocation

// MARK: - Driver Mode, for real (Phase 3 M1/M2)
//
// Everything on the partner dashboard used to be invented by this app: the
// online toggle flipped a Bool, offers arrived from a timer, and a job walked an
// animated route to a fare nobody was paying. That demo is still here, and still
// runs — for somebody who has never been approved, it is the only way to see
// what the screen is for.
//
// What changed is that a *registered* driver or courier now gets the real thing.
// The registry, the offers and the accept are the server's — and as of Phase 4
// M1 both verticals actually ask: `travel` for a ride (3 M3) and `delivery` for
// a courier, which had been simulating one since 2b M4. An empty screen is
// still an honest answer, but it now means a quiet city rather than a product
// with nothing behind it.

extension AppState {

    /// Whether this account is in a dispatch registry — the switch between the
    /// live surface and the demo.
    var isDispatchRegistered: Bool { !dispatchWorkers.isEmpty }

    func dispatchWorker(_ role: PartnerRole) -> DispatchWorkerDTO? {
        dispatchWorkers.first { $0.kind == role.workerKind }
    }

    /// Suspended by the platform — which is a different thing from being offline,
    /// and the app has to be able to say which.
    var isDispatchSuspended: Bool { dispatchWorkers.contains(where: \.suspended) }

    // MARK: Reading

    func refreshDispatch() async {
        guard backendConnected else { return }
        do {
            let mine = try await DispatchStore.shared.me()
            applyDispatch(mine)
        } catch {
            #if DEBUG
            print("Dispatch refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func applyDispatch(_ mine: MyDispatchDTO) {
        dispatchWorkers = mine.workers
        dispatchAssignment = mine.assignment
        dispatchPositionInterval = max(1, mine.positionIntervalSeconds)
        // An offer that expired between the server building this and the phone
        // drawing it is not an offer. Filtering here rather than in the view
        // keeps one definition of "live".
        let now = Date()
        dispatchOffers = mine.offers.filter { $0.expiresAt > now }
        dispatchOnline = mine.workers.contains { $0.status != "OFFLINE" }
        presentLiveOffer()
        // A delivery assignment is only half an answer: dispatch says which job,
        // and `delivery` says what is in the bag. Asked here rather than on a
        // loop of its own, so a courier's screen and their offer book are never
        // one poll apart.
        if mine.assignment?.jobKind == "DELIVERY" || courierJob != nil {
            Task { await refreshCourierJob() }
        }
    }

    /// Puts a real offer into the card the dashboard already draws.
    ///
    /// Reusing the demo's `PartnerJob` shape rather than building a second card
    /// is deliberate — it is the same information in the same place, and two
    /// offer cards would drift. What it must never do is *invent* the missing
    /// half: dispatch sends no fare, because a fare belongs to the vertical that
    /// asked, so the card shows a distance and a pickup and no money. A plausible
    /// number here would be the worst kind of wrong.
    private func presentLiveOffer() {
        guard isDispatchRegistered, let role = partnerDashboardRole else { return }
        guard let offer = dispatchOffers.first else {
            // Only clear a card that was the server's — a demo job on screen for
            // an unregistered account is not ours to remove.
            if partnerJobPhase == .offer, let shown = partnerJob,
               !dispatchOffers.contains(where: { $0.id == shown.id }) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    partnerJob = nil
                    partnerJobPhase = .idle
                }
            }
            return
        }
        if partnerJob?.id == offer.id { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            partnerJob = PartnerJob(
                id: offer.id,
                role: role,
                customerName: offer.jobKind == "RIDE" ? "Rider" : "Customer",
                pickupName: offer.pickupLabel.isEmpty ? "Pickup" : offer.pickupLabel,
                pickupSubtitle: String(format: "%.1f km away", offer.distanceKm),
                dropoffName: offer.dropoffLabel.isEmpty ? "Destination" : offer.dropoffLabel,
                dropoffSubtitle: offer.note,
                distanceKm: offer.distanceKm,
                minutes: 0,
                fare: 0,
                originLat: dispatchWorker(role)?.latitude ?? offer.pickupLatitude,
                originLon: dispatchWorker(role)?.longitude ?? offer.pickupLongitude,
                pickupLat: offer.pickupLatitude,
                pickupLon: offer.pickupLongitude,
                dropoffLat: offer.dropoffLatitude ?? offer.pickupLatitude,
                dropoffLon: offer.dropoffLongitude ?? offer.pickupLongitude)
            partnerJobPhase = .offer
        }
    }

    // MARK: Going on and off the road

    /// The real availability toggle. Refusals are shown rather than swallowed —
    /// "suspended" is something the driver has to act on, and a switch that
    /// silently does nothing reads as a broken app.
    func setDispatchAvailable(_ available: Bool, role: PartnerRole) {
        guard isDispatchRegistered else { return }
        Task {
            do {
                _ = try await DispatchStore.shared.setAvailable(available,
                                                                kind: role.workerKind)
                await refreshDispatch()
                if available {
                    startDispatchDuty()
                } else {
                    stopDispatchDuty()
                }
            } catch {
                showWalletNotice(Self.message(from: error,
                    fallback: available ? "Couldn't go online." : "Couldn't go offline."))
                await refreshDispatch()
            }
        }
    }

    /// While available: report where you are, and ask what's waiting.
    ///
    /// Two loops rather than one, on two intervals, because they cost different
    /// amounts. A position is a 204 with no body and goes at whatever rate the
    /// server asks for; the offer read builds real state and goes slower. Both
    /// stop the moment the driver signs off — a phone reporting a position for
    /// somebody who has gone home is a battery complaint and a privacy one.
    func startDispatchDuty() {
        stopDispatchDuty()
        LiveLocationProvider.shared.startTracking()
        dispatchDutyTracking = true
        dispatchPositionTask = Task { @MainActor in
            while !Task.isCancelled {
                await reportDispatchPosition()
                try? await Task.sleep(nanoseconds: UInt64(dispatchPositionInterval) * 1_000_000_000)
            }
        }
        dispatchPollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                await refreshDispatch()
            }
        }
    }

    func stopDispatchDuty() {
        dispatchPositionTask?.cancel()
        dispatchPositionTask = nil
        dispatchPollTask?.cancel()
        dispatchPollTask = nil
        if dispatchDutyTracking {
            LiveLocationProvider.shared.stopTracking()
            dispatchDutyTracking = false
        }
    }

    private func reportDispatchPosition() async {
        guard let where_ = LiveLocationProvider.shared.currentCoordinate else { return }
        try? await DispatchStore.shared.reportPosition(latitude: where_.latitude,
                                                       longitude: where_.longitude)
    }

    // MARK: Answering an offer

    func acceptDispatchOffer(_ offer: DispatchOfferDTO) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do {
                dispatchAssignment = try await DispatchStore.shared.accept(offer.id)
                dispatchOffers.removeAll { $0.id == offer.id }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                // Losing the race is the normal case, not a failure — say who
                // got there first in the server's own words.
                showWalletNotice(Self.message(from: error,
                                              fallback: "That one's gone."))
                dispatchOffers.removeAll { $0.id == offer.id }
            }
            await refreshDispatch()
            // Accepting a ride is what spends a token (Phase 3 M4) — the vertical
            // charges at confirmation, so the balance on screen is stale the
            // moment this returns.
            await refreshTokens()
            // And accepting a delivery is what gives a courier an order to go
            // and collect (Phase 4 M1).
            if offer.jobKind == "DELIVERY" { await refreshCourierJob() }
        }
    }

    func declineDispatchOffer(_ offer: DispatchOfferDTO) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Optimistic: declining is the one action whose failure changes nothing
        // the driver can see, and waiting on a round trip to clear a card that
        // expires in thirty seconds is worse than being wrong about it.
        dispatchOffers.removeAll { $0.id == offer.id }
        Task {
            try? await DispatchStore.shared.decline(offer.id)
            await refreshDispatch()
        }
    }

    // MARK: What the dashboard renders

    /// Lifetime jobs, from the registry rather than a local counter.
    func dispatchCompleted(_ role: PartnerRole) -> Int {
        dispatchWorker(role)?.completedCount ?? 0
    }

    func dispatchRating(_ role: PartnerRole) -> Double? {
        guard let worker = dispatchWorker(role), worker.ratingCount > 0 else { return nil }
        return worker.rating
    }

    /// "92% of the last 30 days", or nil when nothing has been offered yet.
    func dispatchAcceptanceLabel(_ role: PartnerRole) -> String? {
        guard let rate = dispatchWorker(role)?.last30Days?.acceptanceRate else { return nil }
        return String(format: "%.0f%%", rate)
    }
}

extension PartnerRole {

    /// This app's word for the role, in dispatch's vocabulary.
    var workerKind: String { self == .driver ? "DRIVER" : "COURIER" }

    /// And in `partner`'s, which happens to be the same — but they are two
    /// enums in two modules and writing that down twice is how they stay in
    /// step when one of them grows a third value.
    var partnerKind: String { self == .driver ? "DRIVER" : "COURIER" }
}
