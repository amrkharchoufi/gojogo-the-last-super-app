import SwiftUI
import UIKit

// MARK: - Delivery live wiring (Phase 2b · Milestone 4)
//
// Bridges GojoDelivery onto the deployed `delivery` module. On connect the live
// restaurant catalog replaces the sample one, checkout places a real order, and
// the tracking screen mirrors the backend's fulfilment state instead of running
// its own timer — so the same order looks the same on a second device, and an
// order still in flight is picked back up after a relaunch. Offline (or against
// an empty catalog) the on-device demo in AppState is untouched.

extension AppState {

    // MARK: Addresses

    /// The address this order goes to: the one the user picked, else their
    /// default, else the most recently saved.
    var selectedDeliveryAddress: DeliveryAddress? {
        if let id = selectedDeliveryAddressID,
           let picked = deliveryAddresses.first(where: { $0.id == id }) {
            return picked
        }
        return deliveryAddresses.first(where: \.isDefault) ?? deliveryAddresses.first
    }

    /// What the "Deliver to" rows show.
    var deliveryAddressLabel: String {
        selectedDeliveryAddress?.display ?? "Add a delivery address"
    }

    /// True when checkout can't proceed because there's nowhere to deliver to.
    /// Never for a collection: the address of a pickup is the counter, and
    /// asking for a home one anyway would stop somebody walking to a restaurant
    /// until they had saved somewhere to live.
    func deliveryNeedsAddress(for merchantID: UUID?) -> Bool {
        guard !deliveryWantsPickup, backendConnected, let merchantID,
              DeliveryStore.shared.isRemote(merchantID) else { return false }
        return selectedDeliveryAddress == nil
    }

    // MARK: Collect in store (Phase 4 M4)

    /// Whether every kitchen in the cart offers collection. The switch is only
    /// shown when this is true — an order is one kind, so a cart with one
    /// delivery-only restaurant in it cannot be collected at all.
    var deliveryCartCanBeCollected: Bool {
        guard !deliveryCart.isEmpty else { return false }
        return deliveryCartMerchantIDs.allSatisfy { id in
            deliveryRestaurants.first(where: { $0.id == id })?.offersPickup == true
        }
    }

    /// Flips the whole checkout between delivery and collection, and re-prices
    /// it — the fee, the tip and the discount all move, and a total on screen
    /// that belonged to the other kind is the one thing this must never leave
    /// behind.
    func setDeliveryWantsPickup(_ pickup: Bool) {
        guard pickup != deliveryWantsPickup else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.ggSnappy) {
            deliveryWantsPickup = pickup
            // A tip is the courier's, and a collection has none. Cleared rather
            // than remembered, so the number on screen is the number charged.
            if pickup { deliveryTipCents = 0 }
        }
        Task { await refreshDeliveryQuote() }
    }

    /// Where to walk to for the live order, per kitchen — the copy taken at
    /// order time, so it survives the restaurant editing their own row.
    func deliveryCollectionAddress(_ kitchen: SubOrderDTO) -> String {
        let copied = kitchen.pickupAddress ?? ""
        return copied.isEmpty ? kitchen.merchantName : copied
    }

    func refreshDeliveryAddresses() async {
        guard backendConnected else { return }
        do {
            let saved = try await DeliveryStore.shared.addresses()
            deliveryAddresses = saved
            if let id = selectedDeliveryAddressID, !saved.contains(where: { $0.id == id }) {
                selectedDeliveryAddressID = nil
            }
        } catch {
            #if DEBUG
            print("Delivery addresses refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Creates or updates an address. `editing` non-nil means "save my edits to
    /// this one". The saved address becomes the selected one either way.
    func saveDeliveryAddress(editing: UUID? = nil, label: String, line1: String, note: String,
                             latitude: Double? = nil, longitude: Double? = nil,
                             makeDefault: Bool = false) {
        let street = line1.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !street.isEmpty else { return }
        let body = SaveAddressBody(
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            line1: street,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: latitude,
            longitude: longitude,
            makeDefault: makeDefault)
        Task {
            do {
                let saved = editing == nil
                    ? try await DeliveryStore.shared.createAddress(body)
                    : try await DeliveryStore.shared.updateAddress(editing!, body)
                selectedDeliveryAddressID = saved.id
                await refreshDeliveryAddresses()
            } catch {
                showDeliveryNotice(Self.message(from: error, fallback: "Couldn't save that address."))
                // The list on screen just proved itself stale (someone edited an
                // address that no longer exists) — reconcile with the server.
                await refreshDeliveryAddresses()
            }
        }
    }

    /// Picks an address for this order and makes it the account default, so the
    /// next order (and a second device) starts from the same place.
    func selectDeliveryAddress(_ addressID: UUID) {
        selectedDeliveryAddressID = addressID
        Task {
            do {
                try await DeliveryStore.shared.makeDefaultAddress(addressID)
                await refreshDeliveryAddresses()
            } catch {
                #if DEBUG
                print("Set default address failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func deleteDeliveryAddress(_ addressID: UUID) {
        withAnimation(.ggSnappy) {
            deliveryAddresses.removeAll { $0.id == addressID }
        }
        if selectedDeliveryAddressID == addressID { selectedDeliveryAddressID = nil }
        Task {
            do {
                try await DeliveryStore.shared.deleteAddress(addressID)
            } catch {
                showDeliveryNotice(Self.message(from: error,
                                                fallback: "Couldn't delete that address."))
            }
            await refreshDeliveryAddresses()
        }
    }

    // MARK: Notices

    /// Surfaces a short message over GojoDelivery — the delivery screens have
    /// no other way to admit that something failed.
    func showDeliveryNotice(_ message: String) {
        deliveryNoticeTask?.cancel()
        withAnimation(.ggSnappy) { deliveryNotice = message }
        deliveryNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.ggSnappy) { self?.deliveryNotice = nil }
        }
    }

    func dismissDeliveryNotice() {
        deliveryNoticeTask?.cancel()
        withAnimation(.ggSnappy) { deliveryNotice = nil }
    }

    /// Prefers the backend's own message ("Too late to cancel — your courier is
    /// on the way") over a generic one.
    static func message(from error: Error, fallback: String) -> String {
        if case APIClient.APIError.http(_, let message) = error, let message, !message.isEmpty {
            return message
        }
        return fallback
    }

    // MARK: Catalog

    /// Replaces the restaurant catalog with the live one and picks up whatever
    /// order (if any) the account already has in flight.
    func refreshDelivery() async {
        guard backendConnected else { return }
        do {
            let restaurants = try await DeliveryStore.shared.merchants()
            if !restaurants.isEmpty {
                withAnimation(.easeOut(duration: 0.25)) { deliveryRestaurants = restaurants }
            }
        } catch {
            #if DEBUG
            print("Delivery catalog refresh failed: \(error.localizedDescription)")
            #endif
        }
        await refreshDeliveryAddresses()
        await restoreLiveDeliveryOrder()
        await refreshDeliveryHistory()
    }

    /// Browse returns restaurants without menus (they're only needed once you
    /// open one), so fetch this one's the first time it's opened.
    func loadDeliveryMenuIfNeeded(_ merchantID: UUID) {
        guard backendConnected,
              DeliveryStore.shared.isRemote(merchantID),
              !deliveryMenuLoading.contains(merchantID) else { return }
        if let index = deliveryRestaurants.firstIndex(where: { $0.id == merchantID }),
           !deliveryRestaurants[index].menu.isEmpty { return }
        deliveryMenuLoading.insert(merchantID)
        Task {
            defer { deliveryMenuLoading.remove(merchantID) }
            do {
                let full = try await DeliveryStore.shared.merchant(merchantID)
                if let index = deliveryRestaurants.firstIndex(where: { $0.id == merchantID }) {
                    deliveryRestaurants[index].menu = full.menu
                    deliveryRestaurants[index].storefront = full.storefront
                } else {
                    deliveryRestaurants.append(full)
                }
                await loadDeliveryPromotionsIfNeeded(merchantID, page: full.storefront)
            } catch {
                #if DEBUG
                print("Delivery menu load failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Pull-to-refresh on a restaurant page. Deliberately unconditional, unlike
    /// `loadDeliveryMenuIfNeeded` — an already-loaded menu is exactly what the
    /// user is asking to re-read (a dish sold out, a price moved).
    func reloadDeliveryMenu(_ merchantID: UUID) async {
        guard backendConnected, DeliveryStore.shared.isRemote(merchantID) else { return }
        do {
            let full = try await DeliveryStore.shared.merchant(merchantID)
            if let index = deliveryRestaurants.firstIndex(where: { $0.id == merchantID }) {
                // Menu and storefront only: the browse record carries fields the
                // detail fetch doesn't, and replacing it wholesale would drop them.
                deliveryRestaurants[index].menu = full.menu
                deliveryRestaurants[index].storefront = full.storefront
            } else {
                deliveryRestaurants.append(full)
            }
            await loadDeliveryPromotionsIfNeeded(merchantID, page: full.storefront)
        } catch {
            #if DEBUG
            print("Delivery menu reload failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Loads this restaurant's live promotions, but only when its page shows
    /// one. A `promo_banner` names a promotion by id and nothing else — the
    /// discount itself is the server's, and copying its wording into the block
    /// would have let the banner and the actual deal drift apart.
    func loadDeliveryPromotionsIfNeeded(_ merchantID: UUID, page: [StorefrontBlock]) async {
        let wanted = page.contains { if case .promo = $0 { return true } else { return false } }
        guard wanted, backendConnected else { return }
        do {
            deliveryPromotions[merchantID] = try await DeliveryStore.shared.promotions(merchantID)
        } catch {
            // A banner with nothing behind it simply doesn't render — the rest
            // of the page is unaffected, so this is not worth a notice.
            #if DEBUG
            print("Delivery promotions load failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// The promotion a `promo_banner` names, if it is still live.
    func deliveryPromotion(_ promotionID: UUID, at merchantID: UUID) -> DeliveryPromotionDTO? {
        deliveryPromotions[merchantID]?.first { $0.id == promotionID && $0.active }
    }

    // MARK: Order history

    func refreshDeliveryHistory() async {
        guard backendConnected else { return }
        do {
            let orders = try await DeliveryStore.shared.history()
            // Cancelled orders are in the response too, but "Order again" is
            // about meals that actually arrived.
            deliveryPastOrders = orders
                .filter { $0.status == "DELIVERED" }
                .map(Self.pastOrder)
        } catch {
            #if DEBUG
            print("Delivery history refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static func pastOrder(_ dto: OrderDTO) -> DeliveryPastOrder {
        DeliveryPastOrder(
            id: dto.id,
            restaurantName: dto.merchant.name,
            imageURL: dto.merchant.imageUrl,
            itemsSummary: DeliveryStore.summary(dto.lines),
            totalLabel: DeliveryStore.money(cents: dto.totalCents),
            dateLabel: BackendDate.relative(dto.placedAt),
            rating: dto.rating ?? 0)
    }

    // MARK: Placing an order

    /// Places the cart against the live backend. The tracking screen opens
    /// optimistically; if the call fails the cart is handed back so the order
    /// can be retried rather than silently lost.
    // MARK: Checkout (Phase 2e M3)

    /// True while the cart belongs to live restaurants — the only case where
    /// money is involved at all. A SampleData restaurant still runs the
    /// on-device demo, free of charge.
    ///
    /// Every kitchen in the cart has to be live, not just the first: a mixed
    /// cart cannot be half a real order, and the demo cannot price a real one.
    var deliveryCartIsLive: Bool {
        guard backendConnected, !deliveryCart.isEmpty else { return false }
        return deliveryCartMerchantIDs.allSatisfy { DeliveryStore.shared.isRemote($0) }
    }

    /// What checkout will actually cost. The app deliberately does not compute
    /// this: fees, the discount a code is worth, and whether the wallet covers
    /// it are all the server's answer, and a total the client invented is a
    /// total the client can be wrong about.
    func refreshDeliveryQuote() async {
        guard deliveryCartIsLive, !deliveryCart.isEmpty else {
            deliveryQuote = nil
            return
        }
        let baskets = deliveryCartBaskets
        deliveryQuoting = true
        defer { deliveryQuoting = false }
        let pickup = deliveryWantsPickup
        do {
            deliveryQuote = try await DeliveryStore.shared.quote(
                baskets: baskets,
                promotionCode: deliveryPromotionCode, tipCents: deliveryTipCents,
                pickup: pickup)
        } catch {
            // A refused code is the common case and worth saying out loud; the
            // quote falls back to no code rather than blocking checkout. Since
            // Phase 4 M3 the server only refuses a code that landed on *no*
            // kitchen, so this really does mean "not valid anywhere here".
            deliveryQuote = nil
            if !deliveryPromotionCode.isEmpty {
                showDeliveryNotice(Self.message(from: error, fallback: "That code isn't valid here."))
                deliveryPromotionCode = ""
                deliveryQuote = try? await DeliveryStore.shared.quote(
                    baskets: baskets, promotionCode: nil, tipCents: deliveryTipCents,
                    pickup: pickup)
            }
        }
    }

    /// The cart in the shape the wire takes it: one basket per kitchen.
    var deliveryCartBaskets: [UUID: [DeliveryCartLine]] {
        Dictionary(grouping: deliveryCart, by: \.merchantID)
    }

    /// Tip choices at checkout, in minor units — none, and three round numbers.
    static let deliveryTipOptions = [0, 200, 500, 1_000]

    func setDeliveryTip(_ cents: Int) {
        deliveryTipCents = cents
        Task { await refreshDeliveryQuote() }
    }

    func applyDeliveryPromotionCode(_ code: String) {
        deliveryPromotionCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        Task { await refreshDeliveryQuote() }
    }

    func placeLiveDeliveryOrder(merchantID: UUID) {
        let lines = deliveryCart
        let baskets = deliveryCartBaskets
        let optimisticTotal = Double(deliveryQuote?.totalCents ?? 0) / 100
        showDeliveryCheckout = false
        selectedDeliveryRestaurantID = nil
        deliveryOrderRestaurantID = merchantID
        deliveryOrderTotalLabel = String(format: "$%.2f", optimisticTotal)
        deliveryOrderSummary = lines.map { "\($0.qty)× \($0.item.name)" }.joined(separator: ", ")
        // The slowest kitchen sets the wait, which is what the server will say
        // too — a countdown from the fastest one is a countdown that is wrong
        // the moment the second restaurant accepts.
        let pickup = deliveryWantsPickup
        deliveryOrderIsPickup = pickup
        deliveryEtaMinutes = baskets.keys
            .compactMap { id -> Int? in
                guard let restaurant = deliveryRestaurants.first(where: { $0.id == id }) else {
                    return nil
                }
                // A collection promises the kitchen's own time, which has no
                // courier's journey in it.
                return pickup ? restaurant.pickupEtaMinutes : restaurant.etaMinutes
            }
            .max() ?? 25
        deliveryCourier = nil
        deliveryCourierProgress = 0
        deliveryRating = 0
        deliveryCart = []
        deliveryCartRestaurantID = nil
        withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = .confirmed }

        let code = deliveryPromotionCode
        let tip = deliveryTipCents

        Task {
            do {
                let order = try await DeliveryStore.shared.placeOrder(
                    baskets: baskets,
                    addressId: selectedDeliveryAddress?.id,
                    note: "",
                    promotionCode: code,
                    tipCents: tip,
                    pickup: pickup)
                applyLiveOrder(order)
                startDeliveryPolling()
                deliveryPromotionCode = ""
                deliveryTipCents = 0
                deliveryWantsPickup = false
                deliveryQuote = nil
                // The total just moved out of the spendable balance into escrow.
                await refreshWallet()
            } catch {
                #if DEBUG
                print("Place delivery order failed: \(error.localizedDescription)")
                #endif
                // Take the tracking screen back down and hand the cart back —
                // and say so, rather than leaving the user to guess.
                deliveryCart = lines
                deliveryCartRestaurantID = lines.first?.merchantID ?? merchantID
                deliveryWantsPickup = pickup
                deliveryOrderRestaurantID = nil
                withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = nil }
                showDeliveryCheckout = true

                // 402 is the wallet being short, and it is the one checkout
                // failure with an obvious next step — so offer that step rather
                // than an apology.
                if case APIClient.APIError.http(let status, _) = error, status == 402 {
                    await refreshWallet()
                    showDeliveryNotice(Self.message(from: error,
                                                    fallback: "Your wallet is short. Top up to order."))
                    showWallet = true
                } else {
                    showDeliveryNotice(Self.message(from: error,
                                                    fallback: "Couldn't place your order — your cart is back."))
                }
            }
        }
    }

    /// A tip after the food arrived. Settled straight through — there is
    /// nothing left in escrow to hold it against, and the courier has already
    /// done the work.
    func tipCourier(_ orderID: UUID, cents: Int) {
        Task {
            do {
                _ = try await DeliveryStore.shared.tip(orderID, cents: cents)
                await refreshWallet()
                showDeliveryNotice("Thanks — \(WalletStore.money(cents)) sent to your courier.")
            } catch {
                showDeliveryNotice(Self.message(from: error, fallback: "Couldn't send that tip."))
            }
        }
    }

    // MARK: Tracking

    /// Re-attaches to an order that's still out for delivery (another device,
    /// an app relaunch, a cold start hours later).
    func restoreLiveDeliveryOrder() async {
        do {
            guard let order = try await DeliveryStore.shared.activeOrder() else {
                if deliveryLiveOrderID != nil { clearLiveDeliveryOrder() }
                return
            }
            applyLiveOrder(order)
            startDeliveryPolling()
        } catch {
            #if DEBUG
            print("Active delivery order lookup failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Mirrors the server's fulfilment state onto the tracking screen. Polls by
    /// order id (not `/active`) so a delivered order stays on screen for its
    /// rating instead of disappearing the moment it's no longer "active".
    func startDeliveryPolling() {
        deliveryPollTask?.cancel()
        deliveryPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, !Task.isCancelled, let orderID = self.deliveryLiveOrderID else { return }
                do {
                    let order = try await DeliveryStore.shared.order(orderID)
                    self.applyLiveOrder(order)
                    if order.status == "DELIVERED" || order.status == "CANCELLED" { return }
                } catch {
                    #if DEBUG
                    print("Delivery order poll failed: \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }

    func applyLiveOrder(_ order: OrderDTO) {
        guard let status = DeliveryStore.status(order.status) else {
            // Cancelled — nothing left to track, but somebody has to say why.
            // Since Phase 4 M1 a cancellation is usually not the customer's own:
            // a restaurant turned it down, or nobody there answered at all, and
            // a tracking screen that simply vanished would leave them wondering
            // what they had done.
            if let reason = order.cancelReason, !reason.isEmpty,
               deliveryLiveOrderID == order.id {
                showDeliveryNotice(reason)
            }
            clearLiveDeliveryOrder()
            return
        }
        let wasDelivered = deliveryStatus == .delivered
        deliveryLiveOrderID = order.id
        deliveryOrderRestaurantID = order.merchant.id
        deliveryOrderTotalLabel = DeliveryStore.money(cents: order.totalCents)
        deliveryOrderSummary = DeliveryStore.summary(order.lines)
        deliveryEtaMinutes = order.etaMinutes
        // The server's answer, not this app's intention: an order placed as a
        // delivery stays one however the checkout switch is set now.
        deliveryOrderIsPickup = order.isPickup
        deliveryCourier = order.courier.map(DeliveryStore.courier)
        // "The kitchen is cooking and nobody has taken the delivery" is not a
        // stage of an order — it is a problem with one, which is why it rides
        // beside the status rather than inside it.
        deliveryCourierSearch = order.courierSearch
        // The handoff half (Phase 4 M2). All four are the server's answer and
        // none is computed here — in particular the PIN, which is blank unless
        // the order is live *and* in PIN mode, so the card can render it
        // whenever it is non-empty rather than re-deriving that rule.
        deliveryHandoffMode = order.handoff
        deliveryPin = order.deliveryPin ?? ""
        deliveryProofPhotoURL = order.proofPhotoUrl
        deliveryConversationID = order.conversationId
        // The kitchens on this order (Phase 4 M3). Empty for a backend that
        // predates M3, which the tracking card reads as "one restaurant" —
        // exactly what it always drew.
        deliveryKitchens = order.kitchens
        if let rating = order.rating { deliveryRating = rating }
        // The tracking map reads the restaurant's coordinates out of the
        // catalog; an order placed before this session's browse may not be in it.
        if !deliveryRestaurants.contains(where: { $0.id == order.merchant.id }) {
            loadDeliveryMenuIfNeeded(order.merchant.id)
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            deliveryCourierProgress = order.courierProgress
            deliveryStatus = status
        }
        if status == .delivered, !wasDelivered {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: Cancel / finish

    func cancelLiveDeliveryOrder(_ orderID: UUID) {
        deliveryPollTask?.cancel()
        clearLiveDeliveryOrder()
        Task {
            do {
                _ = try await DeliveryStore.shared.cancel(orderID)
                await refreshDeliveryHistory()
            } catch {
                // The backend refused (the courier already has the food) — put
                // the tracking screen back rather than pretending it's cancelled.
                #if DEBUG
                print("Cancel delivery order failed: \(error.localizedDescription)")
                #endif
                if let order = try? await DeliveryStore.shared.order(orderID),
                   DeliveryStore.status(order.status) != nil {
                    applyLiveOrder(order)
                    startDeliveryPolling()
                }
                showDeliveryNotice(Self.message(from: error,
                                                fallback: "Couldn't cancel that order."))
            }
        }
    }

    /// "Done" on the delivered screen: sends the star rating, if any, and
    /// refreshes the order-again rail.
    func finishLiveDeliveryOrder(_ orderID: UUID) {
        let stars = deliveryRating
        clearLiveDeliveryOrder()
        Task {
            if stars > 0 {
                do {
                    _ = try await DeliveryStore.shared.rate(orderID, stars: stars)
                } catch {
                    #if DEBUG
                    print("Rate delivery order failed: \(error.localizedDescription)")
                    #endif
                }
            }
            await refreshDeliveryHistory()
        }
    }

    func clearLiveDeliveryOrder() {
        deliveryPollTask?.cancel()
        deliveryPollTask = nil
        deliveryLiveOrderID = nil
        deliveryCourier = nil
        deliveryCourierProgress = 0
        deliveryCourierSearch = nil
        deliveryOrderRestaurantID = nil
        deliveryHandoffMode = "CONFIRM"
        deliveryPin = ""
        deliveryProofPhotoURL = nil
        deliveryConversationID = nil
        deliveryKitchens = []
        deliveryOrderIsPickup = false
        deliveryRating = 0
        withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = nil }
    }

    // MARK: How it gets handed over (Phase 4 M2)

    /// Hand it to me · leave it at the door · no code at all.
    ///
    /// Changeable right up until the food arrives, which is the point: nobody
    /// decides at checkout that they will be in the shower when the courier
    /// gets there. Optimistic, because the control *is* the feedback and a
    /// segmented picker that snaps back half a second later reads as a bug —
    /// and the server's answer replaces it either way.
    func setDeliveryHandoffMode(_ mode: String) {
        guard let orderID = deliveryLiveOrderID, mode != deliveryHandoffMode,
              !deliveryHandoffBusy else { return }
        let previous = deliveryHandoffMode
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.ggSnappy) { deliveryHandoffMode = mode }
        deliveryHandoffBusy = true
        Task {
            defer { deliveryHandoffBusy = false }
            do {
                applyLiveOrder(try await DeliveryStore.shared.setHandoffMode(orderID, mode: mode))
            } catch {
                withAnimation(.ggSnappy) { deliveryHandoffMode = previous }
                showDeliveryNotice(Self.message(from: error,
                                                fallback: "Couldn't change how this is handed over."))
            }
        }
    }

    // MARK: One kitchen at a time (Phase 4 M3)

    /// Drops one restaurant from an order that spans several.
    ///
    /// Deliberately not optimistic, unlike the handoff-mode control: this
    /// moves money and can be refused ("that restaurant is already cooking"),
    /// and a row that disappears and comes back is worse than one that takes a
    /// moment. The refreshed order is the answer either way.
    func cancelDeliverySubOrder(_ subOrderID: UUID) {
        guard let orderID = deliveryLiveOrderID, !deliverySubOrderBusy else { return }
        deliverySubOrderBusy = true
        Task {
            defer { deliverySubOrderBusy = false }
            do {
                applyLiveOrder(try await DeliveryStore.shared
                    .cancelSubOrder(orderID, subOrderId: subOrderID))
            } catch {
                showDeliveryNotice(Self.message(from: error,
                                                fallback: "Couldn't cancel that restaurant."))
                // The screen just proved itself stale — that kitchen may have
                // accepted a second ago. Re-read rather than leaving a Cancel
                // button that will keep failing.
                if let order = try? await DeliveryStore.shared.order(orderID) {
                    applyLiveOrder(order)
                }
            }
        }
    }

    /// Opens the thread with whoever is bringing it — the same navigation the
    /// courier's own "Message customer" uses, from the other end of it.
    func messageDeliveryCourier() {
        guard let id = deliveryConversationID else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        openJobConversation(id)
    }
}
