import SwiftUI
import CoreLocation

// MARK: - The trip, from the driver's seat (Phase 3 M3, finally on screen)
//
// Accepting a ride used to end at dispatch: the offer card vanished, the
// assignment sat in `dispatchAssignment`, and nothing drew it — the driver had
// taken a job they could no longer see. This file is the other half: it reads
// the ride behind a RIDE assignment from `travel`, redraws the dashboard's
// existing job card and navigation map from real state, and gives the driver
// the three buttons the trip actually has — arrived, rider aboard, complete.
//
// The negotiation lives here too. Dispatch's offer deliberately carries no
// money, so "not at that price" is a `travel` counteroffer; the card that
// tracks the rider's answer is driven from the same ride read.

extension AppState {

    /// The dispatch assignment's ride id, when the assignment is a ride.
    private var assignedRideID: UUID? {
        guard let assignment = dispatchAssignment, assignment.jobKind == "RIDE" else { return nil }
        return assignment.jobRefId
    }

    // MARK: Reading it

    /// Fetches the ride behind the current assignment (or the one already on
    /// screen) and redraws the driver's card from it.
    ///
    /// Reads `/offered` rather than `/rides/{id}`: for the first moment after a
    /// dispatch accept the ride hasn't confirmed yet — the server does that
    /// from an after-commit listener — so the driver isn't its driver yet, and
    /// the plain read would honestly 404. The offered read is gated on the
    /// dispatch offer book instead, which covers both sides of that instant.
    func refreshDriverRide() async {
        guard backendConnected else { return }
        guard let rideID = driverRide?.id ?? assignedRideID else { return }
        do {
            applyDriverRide(try await TravelStore.shared.offeredRide(rideID))
        } catch {
            #if DEBUG
            print("Driver ride refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Maps the server's ride onto the dashboard the app already draws — the
    /// same `PartnerJob` card and phases the demo used, with real values.
    func applyDriverRide(_ fresh: RideDTO) {
        // A completion that was already shown and dismissed stays dismissed. The
        // ride can arrive here again — a stale dispatch assignment, a read that
        // was in flight when the card was cleared — and re-applying it would
        // resurrect the "Trip complete" card and count the fare a second time.
        if fresh.state == "COMPLETED", settledDriverRideIDs.contains(fresh.id),
           partnerJobPhase == .idle {
            return
        }
        driverRide = fresh
        // Accepted in dispatch but not confirmed in travel yet — nothing to
        // draw; the poll will catch the confirmation a moment later.
        if fresh.isSearching { return }
        guard fresh.isMatched || fresh.isRunning || fresh.state == "COMPLETED" else {
            if fresh.state.hasPrefix("CANCELLED") || fresh.state == "EXPIRED" {
                showWalletNotice(fresh.cancelReason ?? "That trip was cancelled.")
            }
            clearDriverRide()
            return
        }

        let fareMinor = fresh.agreedFareMinor ?? fresh.offeredFareMinor
        let origin = LiveLocationProvider.shared.currentCoordinate
        partnerJob = PartnerJob(
            id: fresh.id,
            role: .driver,
            customerName: fresh.otherPartyName ?? "Rider",
            pickupName: fresh.pickupLabel.isEmpty ? "Pickup" : fresh.pickupLabel,
            pickupSubtitle: "Pick up \(fresh.otherPartyName ?? "your rider") here",
            dropoffName: fresh.dropoffLabel.isEmpty ? "Destination" : fresh.dropoffLabel,
            dropoffSubtitle: fresh.note ?? "",
            distanceKm: Double(fresh.distanceMetres) / 1000,
            minutes: max(1, fresh.durationSeconds / 60),
            fare: Double(fareMinor) / 100,
            customerAvatarURL: fresh.otherPartyAvatarUrl,
            originLat: origin?.latitude ?? fresh.driverLatitude ?? fresh.pickupLatitude,
            originLon: origin?.longitude ?? fresh.driverLongitude ?? fresh.pickupLongitude,
            pickupLat: fresh.pickupLatitude,
            pickupLon: fresh.pickupLongitude,
            dropoffLat: fresh.dropoffLatitude,
            dropoffLon: fresh.dropoffLongitude,
            rideId: fresh.id)

        let phase: PartnerJobPhase = switch fresh.state {
            case "CONFIRMED", "ARRIVING": .toPickup
            case "IN_TRIP": .toDropoff
            default: .completed
        }
        if phase == .completed && partnerJobPhase != .completed {
            stopDriverRidePolling()
            // Count the earnings into the dashboard's "Today" tile once per
            // ride — a phase transition alone is not enough, because a stale
            // read can walk the phase back to idle and complete it again.
            if settledDriverRideIDs.insert(fresh.id).inserted {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                partnerEarningsByRole[PartnerRole.driver.rawValue, default: 0]
                    += Double(fareMinor) / 100
                partnerJobsByRole[PartnerRole.driver.rawValue, default: 0] += 1
                schedulePersist()
                Task {
                    await refreshWorkerWallet()
                    await refreshDispatch()
                }
            }
        }
        if phase != partnerJobPhase {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                partnerJobPhase = phase
            }
        }
    }

    /// Polls the trip while it runs — 3 seconds, because the thing being
    /// watched is a person waiting at a kerb. Stops itself the moment the ride
    /// is over.
    func startDriverRidePolling() {
        stopDriverRidePolling()
        driverRidePollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                guard let rideID = driverRide?.id ?? assignedRideID else { return }
                guard let fresh = try? await TravelStore.shared.offeredRide(rideID) else { continue }
                applyDriverRide(fresh)
                if fresh.isOver { return }
            }
        }
    }

    func stopDriverRidePolling() {
        driverRidePollTask?.cancel()
        driverRidePollTask = nil
    }

    /// Off the screen. Called when the trip ended (however it ended) or the
    /// completed card was dismissed — never mid-trip.
    func clearDriverRide() {
        stopDriverRidePolling()
        driverRide = nil
        if partnerJobPhase != .idle {
            withAnimation(.easeInOut(duration: 0.3)) {
                partnerJob = nil
                partnerJobPhase = .idle
                partnerJobProgress = 0
            }
        }
    }

    // MARK: The three buttons

    func driverArrived() {
        driverRideAction { try await TravelStore.shared.arriving($0) }
    }

    func driverStartTrip() {
        driverRideAction { try await TravelStore.shared.start($0) }
    }

    /// Ends the trip and moves the money. A 402 here is the rider's wallet
    /// coming up short mid-trip — the server's sentence says what to do.
    func driverCompleteTrip() {
        driverRideAction { try await TravelStore.shared.complete($0) }
    }

    func driverCancelTrip() {
        driverRideAction { try await TravelStore.shared.cancel($0, reason: nil) }
    }

    private func driverRideAction(_ op: @escaping (UUID) async throws -> RideDTO) {
        guard let rideID = driverRide?.id, !driverRideBusy else { return }
        driverRideBusy = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            defer { driverRideBusy = false }
            do {
                applyDriverRide(try await op(rideID))
            } catch {
                showWalletNotice(Self.message(from: error,
                                              fallback: "Couldn't update the trip."))
                await refreshDriverRide()
            }
        }
    }

    // MARK: Negotiation — "not at that price"

    /// Posts a counteroffer on the ride behind the offer card. Countering is
    /// answering "no" to the question dispatch asked, so the dispatch offer is
    /// declined too, and the card is replaced by one that waits for the rider.
    func counterDispatchOffer(amountMinor: Int) {
        guard let shown = partnerJob,
              let offer = dispatchOffers.first(where: { $0.id == shown.id }),
              offer.jobKind == "RIDE", !driverRideBusy, amountMinor > 0 else { return }
        driverRideBusy = true
        Task {
            defer { driverRideBusy = false }
            do {
                _ = try await TravelStore.shared.counter(offer.jobRefId,
                                                         amountMinor: amountMinor)
                withAnimation(.easeInOut(duration: 0.25)) {
                    partnerJob = nil
                    partnerJobPhase = .idle
                }
                dispatchOffers.removeAll { $0.id == offer.id }
                Task { try? await DispatchStore.shared.decline(offer.id) }
                driverNegotiation = try? await TravelStore.shared.offeredRide(offer.jobRefId)
                startDriverNegotiationPolling(offer.jobRefId)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                showWalletNotice(Self.message(from: error,
                                              fallback: "Couldn't send that price."))
            }
        }
    }

    /// The rider came back with a number; the driver takes it. What comes back
    /// is a CONFIRMED ride, so this flows straight into the trip.
    func takeRiderOffer(_ offer: RideOfferDTO) {
        guard !driverRideBusy else { return }
        driverRideBusy = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            defer { driverRideBusy = false }
            do {
                let ride = try await TravelStore.shared.takeOffer(offer.rideId, offer.id)
                stopDriverNegotiationPolling()
                driverNegotiation = nil
                await refreshDispatch()
                applyDriverRide(ride)
                startDriverRidePolling()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                showWalletNotice(Self.message(from: error, fallback: "That price is gone."))
                await refreshDriverNegotiation()
            }
        }
    }

    func dismissDriverNegotiation() {
        stopDriverNegotiationPolling()
        withAnimation(.easeInOut(duration: 0.25)) { driverNegotiation = nil }
    }

    func refreshDriverNegotiation() async {
        guard let rideID = driverNegotiation?.id else { return }
        guard let fresh = try? await TravelStore.shared.offeredRide(rideID) else { return }
        await applyDriverNegotiation(fresh)
    }

    /// Follows the ride while the driver's price is on the table.
    func startDriverNegotiationPolling(_ rideID: UUID) {
        stopDriverNegotiationPolling()
        driverNegotiationPollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, driverNegotiation != nil else { return }
                guard let fresh = try? await TravelStore.shared.offeredRide(rideID) else { continue }
                await applyDriverNegotiation(fresh)
            }
        }
    }

    func stopDriverNegotiationPolling() {
        driverNegotiationPollTask?.cancel()
        driverNegotiationPollTask = nil
    }

    private func applyDriverNegotiation(_ fresh: RideDTO) async {
        guard driverNegotiation != nil else { return }
        if fresh.isSearching {
            driverNegotiation = fresh
            // Nothing pending in either direction any more: the price lapsed
            // unanswered. Telling the driver beats a card that never resolves.
            if fresh.liveOffers.isEmpty {
                stopDriverNegotiationPolling()
                withAnimation(.easeInOut(duration: 0.25)) { driverNegotiation = nil }
                showWalletNotice("Your price lapsed without an answer.")
            }
            return
        }
        stopDriverNegotiationPolling()
        withAnimation(.easeInOut(duration: 0.25)) { driverNegotiation = nil }
        if fresh.isMatched || fresh.isRunning {
            // Matched — but to whom? The dispatch assignment is the honest
            // answer: if it names this ride, the rider took *this* driver's
            // price and the trip starts; if not, somebody else got there first.
            await refreshDispatch()
            if assignedRideID == fresh.id {
                applyDriverRide(fresh)
                startDriverRidePolling()
            } else {
                showWalletNotice("The rider went with somebody else.")
            }
        } else if fresh.state == "EXPIRED" {
            showWalletNotice("That trip request expired before the rider answered.")
        } else if fresh.state.hasPrefix("CANCELLED") {
            showWalletNotice("The rider cancelled that trip.")
        }
    }

    // MARK: Estimating before the server answers

    /// Straight-line distance × the same road factor the server prices with —
    /// the offer card's first paint, replaced by the server's own numbers as
    /// soon as the ride read lands. Never zero for a real trip.
    static func estimatedTripKm(_ lat1: Double, _ lon1: Double,
                                _ lat2: Double, _ lon2: Double) -> Double {
        let metres = CLLocation(latitude: lat1, longitude: lon1)
            .distance(from: CLLocation(latitude: lat2, longitude: lon2))
        return metres * 1.3 / 1000
    }

    static func estimatedTripMinutes(km: Double) -> Int {
        max(1, Int((km / 26.0 * 60).rounded()))   // ~26 km/h through a city
    }
}
