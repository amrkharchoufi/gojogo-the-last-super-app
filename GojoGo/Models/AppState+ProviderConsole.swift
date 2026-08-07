import SwiftUI

// MARK: - The provider's side of a booking (Phase 5 · M3)
//
// Six verbs against the customer's three, because everything that decides what
// a job is worth happens on this side: quote, confirm, decline, cancel,
// complete, no-show. Each one is a different amount of money moving, and none
// of them is a status the app may infer — the server is the only thing that
// knows what a cancellation costs at 3pm for a 4pm job.
//
// The calendar is the other half. It is edited as a whole week rather than a
// day at a time, for the same reason the listing editor posts the whole listing:
// a rule that vanished from the form is a rule that is gone, and a patch API
// would leave the two ends free to disagree about which days exist.

extension AppState {

    func openProviderConsole() {
        showProviderConsole = true
    }

    func closeProviderConsole() {
        showProviderConsole = false
    }

    func refreshProviderConsole() async {
        guard backendConnected, isServiceProvider else { return }
        providerConsoleLoading = myProvider == nil
        defer { providerConsoleLoading = false }
        do {
            myProvider = try await ServicesStore.shared.myProvider()
        } catch {
            // Only fatal when there is nothing on screen yet: this runs on every
            // appear and every pull, and a dropped request must not blank a
            // console that was already showing a practice — or take its queue
            // and its money down with it.
            if myProvider == nil {
                showEconomyNotice(Self.message(from: error,
                                               fallback: "Couldn't load your profile."))
                return
            }
            #if DEBUG
            print("Provider refresh failed, keeping what's loaded: \(error.localizedDescription)")
            #endif
        }
        async let catalog = try? await ServicesStore.shared.myServices()
        async let queue = try? await ServicesStore.shared.providerBookings()
        async let rules = try? await ServicesStore.shared.availability()
        async let daysOff = try? await ServicesStore.shared.exceptions()
        async let wallet = try? await ServicesStore.shared.providerWallet()
        async let papers = try? await ServicesStore.shared.documents()
        let (loadedCatalog, loadedQueue, loadedRules, loadedDaysOff, loadedWallet, loadedPapers) =
            await (catalog, queue, rules, daysOff, wallet, papers)
        withAnimation(.easeOut(duration: 0.2)) {
            myServices = loadedCatalog ?? myServices
            providerBookings = loadedQueue ?? providerBookings
            providerAvailability = loadedRules ?? providerAvailability
            providerExceptions = loadedDaysOff ?? providerExceptions
            providerWallet = loadedWallet ?? providerWallet
            providerDocuments = loadedPapers ?? providerDocuments
        }
    }

    // MARK: Profile

    func saveProviderProfile(_ body: ProviderBody) async -> String? {
        do {
            myProvider = try await ServicesStore.shared.updateProvider(body)
            return nil
        } catch {
            return Self.message(from: error, fallback: "Couldn't save your profile.")
        }
    }

    /// Qualification papers: uploaded straight to S3 under a private prefix.
    /// The app keeps an object key and never a readable URL — a certificate is
    /// evidence for a reviewer, not a public document.
    func uploadProviderDocument(_ data: Data, label: String, contentType: String) async -> String? {
        do {
            let document = try await ServicesStore.shared.uploadDocument(
                data, label: label, contentType: contentType)
            withAnimation(.easeOut(duration: 0.2)) { providerDocuments.insert(document, at: 0) }
            return nil
        } catch {
            return Self.message(from: error, fallback: "Couldn't upload that document.")
        }
    }

    // MARK: Catalog

    func saveService(_ serviceId: UUID?, _ body: ServiceBody) async -> String? {
        do {
            let service = serviceId == nil
                ? try await ServicesStore.shared.createService(body)
                : try await ServicesStore.shared.updateService(serviceId!, body)
            withAnimation(.easeOut(duration: 0.2)) {
                if let index = myServices.firstIndex(where: { $0.id == service.id }) {
                    myServices[index] = service
                } else {
                    myServices.insert(service, at: 0)
                }
                if let index = services.firstIndex(where: { $0.id == service.id }) {
                    services[index] = service
                }
                if browsingService?.id == service.id { browsingService = service }
            }
            return nil
        } catch {
            return Self.message(from: error, fallback: "Couldn't save that service.")
        }
    }

    func setServiceActive(_ serviceId: UUID, _ active: Bool) {
        guard let index = myServices.firstIndex(where: { $0.id == serviceId }) else { return }
        let previous = myServices[index]
        Task {
            do {
                let service = try await ServicesStore.shared.setServiceActive(serviceId, active)
                withAnimation(.ggSnappy) {
                    if let index = myServices.firstIndex(where: { $0.id == serviceId }) {
                        myServices[index] = service
                    }
                    if service.active {
                        if !services.contains(where: { $0.id == serviceId }) {
                            services.insert(service, at: 0)
                        }
                    } else {
                        services.removeAll { $0.id == serviceId }
                    }
                }
            } catch {
                withAnimation(.ggSnappy) {
                    if let index = myServices.firstIndex(where: { $0.id == serviceId }) {
                        myServices[index] = previous
                    }
                }
                showEconomyNotice(Self.message(
                    from: error, fallback: "Couldn't change that service."))
            }
        }
    }

    // MARK: The calendar

    /// Replaces the whole week. Nothing is optimistic: an availability list the
    /// app believes and the server doesn't is a customer being offered an hour
    /// that will be refused.
    func saveAvailability(_ rules: [AvailabilityRuleBody]) async -> String? {
        do {
            let saved = try await ServicesStore.shared.replaceAvailability(rules)
            withAnimation(.easeOut(duration: 0.2)) { providerAvailability = saved }
            return nil
        } catch {
            return Self.message(from: error, fallback: "Couldn't save your hours.")
        }
    }

    func addDayOff(_ day: Date) {
        Task {
            do {
                try await ServicesStore.shared.addException(day)
                providerExceptions = (try? await ServicesStore.shared.exceptions())
                    ?? providerExceptions
            } catch {
                showEconomyNotice(Self.message(from: error, fallback: "Couldn't book that day off."))
            }
        }
    }

    func removeDayOff(_ raw: String) {
        guard let day = Self.parseDay(raw) else { return }
        Task {
            do {
                try await ServicesStore.shared.removeException(day)
                providerExceptions = (try? await ServicesStore.shared.exceptions())
                    ?? providerExceptions
            } catch {
                showEconomyNotice(Self.message(from: error, fallback: "Couldn't undo that day off."))
            }
        }
    }

    /// `yyyy-MM-dd` back into a date, in the device's own zone — the same one
    /// `ServicesStore.day` wrote it in.
    static func parseDay(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }

    // MARK: The booking queue

    /// Every provider verb goes through here: one call, one settled row, one
    /// sentence when it is refused. They are listed rather than generalised
    /// because the refusals differ — declining a confirmed booking and
    /// completing an unstarted one fail for different reasons, and the server's
    /// message is the one worth showing.
    func providerBookingAction(_ booking: BookingDTO, _ action: ProviderBookingAction) {
        Task {
            do {
                let updated: BookingDTO
                switch action {
                case .confirm:  updated = try await ServicesStore.shared.confirm(booking.id)
                case .decline:  updated = try await ServicesStore.shared.decline(booking.id)
                case .cancel:   updated = try await ServicesStore.shared.cancelAsProvider(booking.id)
                case .complete: updated = try await ServicesStore.shared.complete(booking.id)
                case .noShow:   updated = try await ServicesStore.shared.noShow(booking.id)
                }
                applyBooking(updated)
                // Completing and no-show both move money; the wallet card on
                // this same screen would otherwise show yesterday's number.
                providerWallet = try? await ServicesStore.shared.providerWallet()
            } catch {
                showEconomyNotice(Self.message(from: error, fallback: action.failureSentence))
            }
        }
    }

    /// Names a price on a quote-only job. It does not confirm anything — the
    /// customer's acceptance does, and pays at the same moment.
    func quoteBooking(_ bookingId: UUID, priceCents: Int64) async -> String? {
        do {
            let booking = try await ServicesStore.shared.quote(bookingId, priceCents: priceCents)
            applyBooking(booking)
            return nil
        } catch {
            return Self.message(from: error, fallback: "Couldn't send that quote.")
        }
    }

    func replyToServiceReview(_ reviewId: UUID, body: String) async -> String? {
        do {
            let review = try await ServicesStore.shared.replyToReview(reviewId, body: body)
            withAnimation(.easeOut(duration: 0.2)) {
                if let index = serviceReviews.firstIndex(where: { $0.id == review.id }) {
                    serviceReviews[index] = review
                }
            }
            return nil
        } catch {
            return Self.message(from: error, fallback: "Couldn't post that reply.")
        }
    }

    // MARK: Getting the money out (Phase 5 · M5)
    //
    // A practice's earnings settle into its own payee balance, not the person's
    // Gojo Wallet — the same separation the shop has, and the same Stripe
    // Connect path out.

    func startProviderPayoutOnboarding() {
        guard !payeePayoutBusy else { return }
        payeePayoutBusy = true
        Task {
            defer { payeePayoutBusy = false }
            do {
                let link = try await ServicesStore.shared.providerPayoutOnboardingLink()
                guard let url = URL(string: link) else {
                    showEconomyNotice("Couldn't open the payout setup page.")
                    return
                }
                _ = await CheckoutSession().present(url)
                providerWallet = (try? await ServicesStore.shared.providerWallet()) ?? providerWallet
            } catch {
                showEconomyNotice(Self.message(
                    from: error, fallback: "Couldn't start payout setup."))
            }
        }
    }

    func requestProviderPayout(_ amountMinor: Int64) {
        guard !payeePayoutBusy else { return }
        payeePayoutBusy = true
        Task {
            defer { payeePayoutBusy = false }
            do {
                let payout = try await ServicesStore.shared.providerPayOut(amountMinor: amountMinor)
                providerWallet = (try? await ServicesStore.shared.providerWallet()) ?? providerWallet
                showEconomyNotice(payout.status == "SENT"
                    ? "\(EconomyStore.formatPrice(cents: payout.amountMinor, currency: payout.currency)) is on its way to your bank."
                    : (payout.failureReason.isEmpty
                       ? "That payout didn't go through."
                       : payout.failureReason))
            } catch {
                showEconomyNotice(Self.message(from: error, fallback: "Couldn't pay that out."))
            }
        }
    }
}

/// The five provider verbs that take no argument. `quote` is deliberately not
/// one of them — it carries a number, and a number is a different kind of tap.
enum ProviderBookingAction {
    case confirm, decline, cancel, complete, noShow

    var label: String {
        switch self {
        case .confirm: return "Confirm"
        case .decline: return "Decline"
        case .cancel: return "Cancel"
        case .complete: return "Mark done"
        case .noShow: return "No-show"
        }
    }

    var failureSentence: String {
        switch self {
        case .confirm: return "Couldn't confirm that booking."
        case .decline: return "Couldn't decline that booking."
        case .cancel: return "Couldn't cancel that booking."
        case .complete: return "Couldn't mark that done."
        case .noShow: return "Couldn't mark that a no-show."
        }
    }

    /// The ones that need asking twice. A no-show takes the customer's whole
    /// payment and a cancel gives it back — neither is a tap to take on trust.
    var needsConfirmation: Bool {
        self == .cancel || self == .noShow || self == .decline
    }
}
