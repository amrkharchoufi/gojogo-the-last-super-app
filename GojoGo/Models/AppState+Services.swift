import SwiftUI

// MARK: - Services on the phone (Phase 5 · M3)
//
// Booking somebody's time rather than buying a thing, and the whole surface
// bends around one asymmetry: half the services in the catalog have no price,
// because the provider has to look at the job first.
//
// So there are two ways in, and they are deliberately not made to look alike.
// A priced service is *requested* — money held, provider answers yes or no. A
// quote-only service is *asked about* — nothing is held, the provider names a
// number, and accepting that number pays and confirms in one act, because they
// already said yes by naming it. A customer should be able to tell which of the
// two they are doing before they tap, which is what `priceLabel` is for.

extension AppState {

    // MARK: Browse

    /// Same wholesale replace as the shop catalog, and the same one exception:
    /// whatever service page is open survives a refresh that no longer lists it,
    /// so a page doesn't empty itself under somebody mid-read.
    func refreshServices() async {
        guard backendConnected else { return }
        servicesLoading = services.isEmpty
        defer { servicesLoading = false }
        do {
            let page = try await ServicesStore.shared.browse(category: serviceCategory)
            servicesNextBefore = page.nextBefore
            let servedIDs = Set(page.items.map(\.id))
            let openService = browsingService.flatMap { servedIDs.contains($0.id) ? nil : $0 }
            withAnimation(.easeOut(duration: 0.25)) {
                services = page.items + (openService.map { [$0] } ?? [])
            }
        } catch {
            #if DEBUG
            print("Services refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    func selectServiceCategory(_ category: String) {
        guard serviceCategory != category else { return }
        serviceCategory = category
        servicesNextBefore = nil
        Task { await refreshServices() }
    }

    func loadMoreServicesIfNeeded(after serviceID: UUID) {
        guard backendConnected,
              !servicesLoadingMore,
              let cursor = servicesNextBefore,
              let index = services.firstIndex(where: { $0.id == serviceID }),
              index >= services.count - 3 else { return }
        servicesLoadingMore = true
        Task {
            defer { servicesLoadingMore = false }
            do {
                let page = try await ServicesStore.shared.browse(category: serviceCategory,
                                                                 before: cursor)
                servicesNextBefore = page.nextBefore
                let existing = Set(services.map(\.id))
                services.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            } catch {
                #if DEBUG
                print("Services page load failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: Whose service is this

    /// The provider row this account owns, if it owns one. Same shape as
    /// `ownShopId`: the roles call knows it from the first connect, and the
    /// console's copy is only the fallback.
    var ownProviderId: UUID? { myProviderId ?? myProvider?.id }

    /// True when this service is one of ours. Nobody books their own time —
    /// the server refuses it ("That's your own service"), and a calendar of
    /// times to pick from is a strange thing to offer somebody who wrote it.
    func isOwnService(_ service: ServiceDTO) -> Bool {
        if let mine = ownProviderId, mine == service.providerId { return true }
        return myServices.contains { $0.id == service.id }
    }

    // MARK: The service page

    /// Opens a service and asks for its slots and reviews behind it.
    ///
    /// The slots are fetched every single time, never cached with the service:
    /// an availability list is stale the moment anybody else books, and a stale
    /// one offers a time that will be refused with the customer's finger
    /// already on it. Not fetched at all on our own service: the page shows no
    /// picker there, so the request would only be a round trip nobody reads.
    func openService(_ service: ServiceDTO) {
        browsingService = service
        serviceSlots = nil
        serviceReviews = []
        if !isOwnService(service) { loadServiceSlots(service.id) }
        Task {
            let reviews = try? await ServicesStore.shared.reviews(service.id)
            if browsingService?.id == service.id {
                serviceReviews = reviews ?? []
            }
        }
    }

    func openService(id: UUID) {
        if let known = services.first(where: { $0.id == id }) {
            openService(known)
            return
        }
        Task {
            do {
                let service = try await ServicesStore.shared.service(id)
                openService(service)
            } catch {
                showEconomyNotice("That service isn't listed any more.")
            }
        }
    }

    func loadServiceSlots(_ serviceID: UUID, from: Date? = nil) {
        serviceSlotsLoading = true
        Task {
            defer { serviceSlotsLoading = false }
            let slots = try? await ServicesStore.shared.slots(serviceID, from: from)
            guard browsingService?.id == serviceID else { return }
            withAnimation(.easeOut(duration: 0.2)) { serviceSlots = slots }
        }
    }

    func closeService() {
        browsingService = nil
        serviceSlots = nil
        serviceReviews = []
    }

    /// Out of the provider's own service page and into their console. Both are
    /// full-screen covers owned by `RootView`, and raising the second flag in
    /// the same frame as lowering the first loses the presentation — so the
    /// console waits for the page to finish leaving.
    func manageOwnService() {
        closeService()
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            openProviderConsole()
        }
    }

    // MARK: Booking

    /// Requests a booking at a slot. Returns nil on success, or the sentence
    /// to show — including the server's own, which is the one that knows why a
    /// slot it offered thirty seconds ago is gone.
    func requestBooking(_ service: ServiceDTO, at slot: String, note: String) async -> String? {
        guard backendConnected else { return "You're not connected — try again in a moment." }
        guard !isOwnService(service) else {
            return "This is your own service — bookings on it come from other people."
        }
        do {
            let booking = try await ServicesStore.shared.book(BookingRequestBody(
                serviceId: service.id,
                startsAt: slot,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
            withAnimation(.ggSnappy) {
                bookings.insert(booking, at: 0)
                browsingService = nil
                showBookings = true
            }
            // A priced booking held money on the way in.
            await refreshWallet()
            return nil
        } catch {
            // The slot list this came from is now provably stale, whatever the
            // reason — re-ask rather than leave the taken time on screen.
            loadServiceSlots(service.id)
            return Self.message(from: error, fallback: "Couldn't request that booking.")
        }
    }

    func refreshBookings() async {
        guard backendConnected else { return }
        do {
            let mine = try await ServicesStore.shared.myBookings()
            withAnimation(.easeOut(duration: 0.2)) { bookings = mine }
        } catch {
            #if DEBUG
            print("Bookings refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Accepting a quote pays and confirms together, so this is the moment the
    /// money leaves — which is why the UI names the number before asking.
    func acceptBookingQuote(_ bookingId: UUID) {
        Task {
            do {
                let booking = try await ServicesStore.shared.acceptQuote(bookingId)
                applyBooking(booking)
                await refreshWallet()
            } catch {
                showEconomyNotice(Self.message(
                    from: error, fallback: "Couldn't accept that quote."))
            }
        }
    }

    func cancelBooking(_ bookingId: UUID) {
        Task {
            do {
                let booking = try await ServicesStore.shared.cancelBooking(bookingId)
                applyBooking(booking)
                await refreshWallet()
            } catch {
                showEconomyNotice(Self.message(
                    from: error, fallback: "Couldn't cancel that booking."))
            }
        }
    }

    func reviewService(bookingId: UUID, serviceId: UUID, rating: Int, body: String) async -> String? {
        do {
            let review = try await ServicesStore.shared.review(serviceId, ServiceReviewBody(
                bookingId: bookingId, rating: rating,
                body: body.trimmingCharacters(in: .whitespacesAndNewlines)))
            if browsingService?.id == serviceId {
                withAnimation(.easeOut(duration: 0.2)) {
                    serviceReviews.removeAll { $0.authorId == review.authorId }
                    serviceReviews.insert(review, at: 0)
                }
            }
            return nil
        } catch {
            return Self.message(from: error, fallback: "Couldn't post that review.")
        }
    }

    /// Folds a booking into both lists — the customer's and, when this account
    /// is also the provider, their queue.
    func applyBooking(_ booking: BookingDTO) {
        withAnimation(.easeOut(duration: 0.2)) {
            if let index = bookings.firstIndex(where: { $0.id == booking.id }) {
                bookings[index] = booking
            }
            if let index = providerBookings.firstIndex(where: { $0.id == booking.id }) {
                providerBookings[index] = booking
            }
        }
    }

    /// Opens the thread a booking carries. Every booking has one, with a
    /// context card naming the job — the same seam a listing chat uses.
    func openBookingThread(_ booking: BookingDTO) {
        guard let conversationId = booking.conversationId else {
            showEconomyNotice("This booking has no thread yet.")
            return
        }
        showBookings = false
        browsingService = nil
        enterMyWorld()
        guard !needsWorldSetup else {
            pendingSellerConversation = (conversationId, "")
            return
        }
        openWorldConversation(conversationId)
    }
}
