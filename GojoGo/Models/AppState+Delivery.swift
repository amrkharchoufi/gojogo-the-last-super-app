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
    func deliveryNeedsAddress(for merchantID: UUID?) -> Bool {
        guard backendConnected, let merchantID,
              DeliveryStore.shared.isRemote(merchantID) else { return false }
        return selectedDeliveryAddress == nil
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
                } else {
                    deliveryRestaurants.append(full)
                }
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
                // Menu only: the browse record carries fields the detail fetch
                // doesn't, and replacing it wholesale would drop them.
                deliveryRestaurants[index].menu = full.menu
            } else {
                deliveryRestaurants.append(full)
            }
        } catch {
            #if DEBUG
            print("Delivery menu reload failed: \(error.localizedDescription)")
            #endif
        }
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
    func placeLiveDeliveryOrder(merchantID: UUID) {
        let lines = deliveryCart
        let optimisticTotal = deliveryCartTotal
        showDeliveryCheckout = false
        selectedDeliveryRestaurantID = nil
        deliveryOrderRestaurantID = merchantID
        deliveryOrderTotalLabel = String(format: "$%.2f", optimisticTotal)
        deliveryOrderSummary = lines.map { "\($0.qty)× \($0.item.name)" }.joined(separator: ", ")
        deliveryEtaMinutes = deliveryRestaurants.first(where: { $0.id == merchantID })?.etaMinutes ?? 25
        deliveryCourier = nil
        deliveryCourierProgress = 0
        deliveryRating = 0
        deliveryCart = []
        deliveryCartRestaurantID = nil
        withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = .confirmed }

        Task {
            do {
                let order = try await DeliveryStore.shared.placeOrder(
                    merchantId: merchantID,
                    lines: lines,
                    addressId: selectedDeliveryAddress?.id,
                    note: "")
                applyLiveOrder(order)
                startDeliveryPolling()
            } catch {
                #if DEBUG
                print("Place delivery order failed: \(error.localizedDescription)")
                #endif
                // Take the tracking screen back down and hand the cart back —
                // and say so, rather than leaving the user to guess.
                deliveryCart = lines
                deliveryCartRestaurantID = merchantID
                deliveryOrderRestaurantID = nil
                withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = nil }
                showDeliveryNotice(Self.message(from: error,
                                                fallback: "Couldn't place your order — your cart is back."))
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
            // Cancelled — nothing left to track.
            clearLiveDeliveryOrder()
            return
        }
        let wasDelivered = deliveryStatus == .delivered
        deliveryLiveOrderID = order.id
        deliveryOrderRestaurantID = order.merchant.id
        deliveryOrderTotalLabel = DeliveryStore.money(cents: order.totalCents)
        deliveryOrderSummary = DeliveryStore.summary(order.lines)
        deliveryEtaMinutes = order.etaMinutes
        deliveryCourier = order.courier.map(DeliveryStore.courier)
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
        deliveryOrderRestaurantID = nil
        deliveryRating = 0
        withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = nil }
    }
}
