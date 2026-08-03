import SwiftUI
import CoreLocation

// MARK: - Real rides (Phase 3 M3)
//
// GojoTravel's phases already described a real journey — search, choose, match,
// en route, in trip, complete — they were just being driven by a timer and a
// sample driver. The states line up almost exactly with the server's, so what
// changed is who moves them: a `Task.sleep` before, a ride row now.
//
// The simulation is still here and still runs when there is no backend, because
// that is what makes the screen demoable on a laptop with no account. What must
// never happen is the reverse — a *real* rider watching an invented car — so the
// branch is on `backendConnected` and on whether a real ride exists, never on a
// debug flag.

extension AppState {

    /// The live server-side ride, if there is one. Non-nil is what makes every
    /// action on this screen real rather than simulated.
    var hasLiveRide: Bool { ride != nil }

    var rideFareLabel: String {
        guard let ride else { return "" }
        return WalletStore.money(ride.agreedFareMinor ?? ride.offeredFareMinor,
                                 currency: ride.currency)
    }

    // MARK: Quoting

    /// Prices every category for the chosen destination.
    ///
    /// Replaces `SampleData.rideOptions` when connected. The fares are the
    /// server's — this app has never computed one and must not start.
    func quoteRide(to place: TravelPlace) async {
        guard backendConnected else { return }
        do {
            let quote = try await TravelStore.shared.quote(
                from: (travelPickup.latitude, travelPickup.longitude),
                to: (place.latitude, place.longitude))
            rideQuote = quote
            travelRideOptions = quote.categories.map { category in
                RideOption(name: Self.categoryName(category.category),
                           tagline: Self.categoryTagline(category.category),
                           etaMinutes: max(1, quote.durationSeconds / 60),
                           price: WalletStore.money(category.suggestedFareMinor,
                                                    currency: quote.currency),
                           capacity: Self.categoryCapacity(category.category),
                           icon: Self.categoryIcon(category.category))
            }
            selectedRide = travelRideOptions.first
        } catch {
            // Falls through to whatever SampleData already put on screen — a
            // failed quote should not empty the picker somebody is looking at.
            #if DEBUG
            print("Ride quote failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// The category behind the option the rider picked. Matched by position,
    /// because the options were built from the quote in order.
    private var selectedCategory: String? {
        guard let selected = selectedRide,
              let index = travelRideOptions.firstIndex(where: { $0.id == selected.id }),
              let categories = rideQuote?.categories, index < categories.count else { return nil }
        return categories[index].category
    }

    // MARK: Requesting

    /// Books the ride for real, at the suggested price or the rider's own.
    ///
    /// A 402 here is the wallet being short — rides have no escrow, so the
    /// server checks at request rather than letting somebody be driven across a
    /// city they cannot pay for.
    func requestRide(offeringMinor: Int? = nil) {
        guard backendConnected, let destination = travelDropoff,
              let category = selectedCategory else {
            confirmTravelRide()   // the demo, for an account with no backend
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) { travelPhase = .matching }
        Task {
            do {
                let created = try await TravelStore.shared.request(RequestRideBody(
                    category: category,
                    pickupLatitude: travelPickup.latitude,
                    pickupLongitude: travelPickup.longitude,
                    pickupLabel: travelPickup.name,
                    dropoffLatitude: destination.latitude,
                    dropoffLongitude: destination.longitude,
                    dropoffLabel: destination.name,
                    note: nil,
                    offeredFareMinor: offeringMinor))
                apply(created)
                startRidePolling()
            } catch {
                withAnimation(.easeInOut(duration: 0.25)) { travelPhase = .choosingRide }
                showWalletNotice(Self.message(from: error,
                    fallback: "Couldn't request that ride."))
            }
        }
    }

    // MARK: Following it

    func refreshRide() async {
        guard backendConnected else { return }
        // do/catch rather than `try?`, and the distinction is the whole point:
        // Swift flattens `try?` on an optional-returning call, which would make
        // "the network blinked" indistinguishable from "there is no ride" — and
        // clear a live trip off the screen every time a request failed.
        do {
            // A tracked ride is refreshed by id, never via /live: the live read
            // excludes COMPLETED (correctly — a finished trip is not "in a
            // car"), so refreshing a just-completed trip through it erased the
            // rating screen at the exact moment the completion push arrived.
            if let current = ride {
                apply(try await TravelStore.shared.ride(current.id))
            } else if let live = try await TravelStore.shared.live() {
                apply(live)
            } else {
                clearRide()
            }
        } catch {
            #if DEBUG
            print("Ride refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Puts a server ride on the rider's screen from outside the normal flow —
    /// a completion push tapped after the app was relaunched, when nothing was
    /// being tracked. The caller has already established this is the rider's
    /// seat; a live ride also restarts the poll that follows the car.
    func adoptRiderRide(_ fresh: RideDTO) {
        apply(fresh)
        if !fresh.isOver { startRidePolling() }
    }

    /// Polls while a ride is live.
    ///
    /// Two seconds, faster than any other poll in this app, because the thing
    /// being watched is a car approaching a person. It stops the moment the ride
    /// ends — a phone polling for a trip that finished is a battery complaint.
    func startRidePolling() {
        stopRidePolling()
        ridePollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, let current = ride else { return }
                guard let fresh = try? await TravelStore.shared.ride(current.id) else { continue }
                apply(fresh)
                if fresh.isOver { return }
            }
        }
    }

    func stopRidePolling() {
        ridePollTask?.cancel()
        ridePollTask = nil
    }

    /// Maps one server ride onto the screen the app already draws.
    private func apply(_ fresh: RideDTO) {
        let wasOver = ride?.isOver ?? false
        ride = fresh
        // The driver card and the moving marker: real values now, in the same
        // struct the simulation used, so the whole en-route UI is reused.
        if fresh.isMatched || fresh.isRunning {
            travelDriver = TravelDriver(
                id: fresh.otherPartyId ?? fresh.id,
                name: fresh.otherPartyName ?? "Your driver",
                rating: 5.0,
                trips: 0,
                vehicle: fresh.vehicleLabel ?? "",
                plate: fresh.vehiclePlate ?? "",
                etaMinutes: max(1, fresh.durationSeconds / 60),
                avatarURL: fresh.otherPartyAvatarUrl,
                latitude: fresh.driverLatitude ?? fresh.pickupLatitude,
                longitude: fresh.driverLongitude ?? fresh.pickupLongitude)
        }
        let phase: TravelPhase = switch fresh.state {
            case "REQUESTED", "NEGOTIATING": .matching
            case "CONFIRMED", "ARRIVING": .enRoute
            case "IN_TRIP": .inTrip
            case "COMPLETED": .completed
            default: .home
        }
        if phase == .completed && travelPhase != .completed {
            // The trip just ended, which is when the server mints the vehicle
            // verification invite. The screen's own `.task` loaded invites at
            // appear — before this trip existed — so without this reload the
            // push says "help us check the car" and the app shows nothing.
            Task { await loadVerificationInvites() }
        }
        if phase != travelPhase {
            withAnimation(.easeInOut(duration: 0.3)) { travelPhase = phase }
        }
        if fresh.isOver && !wasOver {
            stopRidePolling()
            if fresh.state == "EXPIRED" {
                showWalletNotice("Nobody nearby was free. Try again, or offer a little more.")
            } else if fresh.state.hasPrefix("CANCELLED") {
                showWalletNotice(fresh.cancelReason ?? "That ride was cancelled.")
            }
        }
    }

    private func clearRide() {
        stopRidePolling()
        ride = nil
        travelDriver = nil
        // The safety pack belongs to a trip, not to a session: a share link on
        // screen after the trip it pointed at is gone would invite somebody to
        // send a dead URL to the person waiting for them (Phase 3 M5).
        tripShare = nil
        sos = nil
        confirmingSos = false
        if travelPhase == .matching || travelPhase == .enRoute || travelPhase == .inTrip {
            withAnimation(.easeInOut(duration: 0.3)) { travelPhase = .home }
        }
    }

    // MARK: Negotiating

    /// Takes a driver's counteroffer. A 409 here is the normal case — somebody
    /// else took the trip — and is reported in the server's own words.
    func acceptRideOffer(_ offer: RideOfferDTO) {
        guard let ride else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do {
                apply(try await TravelStore.shared.acceptOffer(ride.id, offer.id))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                showWalletNotice(Self.message(from: error, fallback: "That price is gone."))
                await refreshRide()
            }
        }
    }

    func declineRideOffer(_ offer: RideOfferDTO) {
        guard let ride else { return }
        Task {
            try? await TravelStore.shared.declineOffer(ride.id, offer.id)
            await refreshRide()
        }
    }

    /// One more round, addressed to that driver alone — three drivers countering
    /// is three private conversations, not an auction.
    func counterRideOffer(_ offer: RideOfferDTO, amountMinor: Int) {
        guard let ride else { return }
        Task {
            do {
                _ = try await TravelStore.shared.counterBack(ride.id, offer.id,
                                                             amountMinor: amountMinor)
                await refreshRide()
            } catch {
                showWalletNotice(Self.message(from: error, fallback: "Couldn't send that price."))
            }
        }
    }

    // MARK: Ending it

    func cancelRide(reason: String? = nil) {
        guard backendConnected, let ride else {
            cancelTravelRide()   // the demo
            return
        }
        Task {
            do {
                apply(try await TravelStore.shared.cancel(ride.id, reason: reason))
            } catch {
                showWalletNotice(Self.message(from: error, fallback: "Couldn't cancel that."))
            }
            await refreshRide()
        }
    }

    func rateRide(_ stars: Int) {
        guard backendConnected, let ride else {
            travelRating = stars
            return
        }
        travelRating = stars
        Task {
            _ = try? await TravelStore.shared.rate(ride.id, stars: stars)
            clearRide()
        }
    }

    // MARK: Category vocabulary
    //
    // The server speaks vehicles (BIKE, CAR, XL) because that is what dispatch
    // matches on. A rider reads service names. Translating here rather than on
    // the server keeps one vocabulary in the matching and one in the product.

    static func categoryName(_ category: String) -> String {
        switch category {
        case "BIKE":    return "GojoBike"
        case "SCOOTER": return "GojoMoto"
        case "CAR":     return "GojoGo"
        case "COMFORT": return "GojoComfort"
        case "XL":      return "GojoXL"
        case "VAN":     return "GojoVan"
        default:        return category.capitalized
        }
    }

    static func categoryTagline(_ category: String) -> String {
        switch category {
        case "BIKE":    return "Cheapest, one passenger"
        case "SCOOTER": return "Quick through traffic"
        case "CAR":     return "Everyday rides"
        case "COMFORT": return "Newer cars, more room"
        case "XL":      return "Six seats"
        case "VAN":     return "Luggage and then some"
        default:        return ""
        }
    }

    static func categoryCapacity(_ category: String) -> Int {
        switch category {
        case "BIKE", "SCOOTER": return 1
        case "XL", "VAN":       return 6
        default:                return 4
        }
    }

    static func categoryIcon(_ category: String) -> String {
        switch category {
        case "BIKE":            return "bicycle"
        case "SCOOTER":         return "scooter"
        case "XL", "VAN":       return "bus.fill"
        default:                return "car.fill"
        }
    }
}
