import SwiftUI
import UIKit

// MARK: - Running a restaurant on GojoDelivery (Phase 2b · Milestone 6)
//
// The half of GojoDelivery that has never existed: a restaurant owner with a
// storefront and a menu they control, instead of a catalog only a Flyway
// migration could write.
//
// **Restaurants are created in Gojo Admin, not in this app** (2026-07-27). The
// backend `partner` module still owns the whole journey — application, KYC
// documents, human review — and provisioning still runs through
// `delivery.MerchantProvisioningApi`; the operator just drives it from the admin
// tool. All the app does is read *whether* this user manages a restaurant, and
// then let them run it. See `merchantDashboardEnabled` below for the switch that
// turns even that off.
//
// Note this is the *merchant* side. `AppState`'s older `partnerRoles` /
// `partnerApplication` are the driver-and-courier prototype, which waits on the
// Phase 3 dispatch module; the two never touch.

extension AppState {

    // MARK: Derived state

    /// **The merchant surface as a whole.** On, a restaurant owner gets the
    /// dashboard — open/closed, storefront, menu editor — from inside the app.
    /// Off, GojoDelivery is purely a buyer's app and every restaurant is run
    /// from Gojo Admin.
    ///
    /// Left on pending that decision (2026-07-27). It gates the header chip,
    /// which is the only way into the sheet, so this one constant is the whole
    /// switch.
    static let merchantDashboardEnabled = true

    /// True once this user actually has a restaurant to manage — the account is
    /// provisioned. A suspended owner still counts: they need to be able to see
    /// why, and their menu is still theirs.
    var managesRestaurant: Bool { merchantAccount?.merchantID != nil }

    /// Whether to show the GojoDelivery header chip at all.
    var showsMerchantEntry: Bool {
        Self.merchantDashboardEnabled && backendConnected && managesRestaurant
    }

    /// True while the restaurant is live in the catalog.
    var isMerchantPartner: Bool { merchantAccount?.status == .approved }

    /// What the header chip reads.
    var merchantChipLabel: String { merchantAccount?.status.chipLabel ?? "Your restaurant" }

    var merchantChipIcon: String { merchantAccount?.status.icon ?? "storefront" }

    // MARK: Loading

    /// Called on connect and whenever the merchant sheet opens. Cheap: one GET,
    /// plus a second only for someone who manages a restaurant.
    func refreshMerchantPartner() async {
        guard backendConnected, Self.merchantDashboardEnabled else { return }
        do {
            let account = try await PartnerStore.shared.me()
            merchantAccount = account
            if account?.merchantID != nil {
                await refreshMerchantStorefront()
            } else {
                merchantStorefront = nil
            }
        } catch {
            #if DEBUG
            print("Partner refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    func refreshMerchantStorefront() async {
        guard backendConnected else { return }
        do {
            merchantStorefront = try await PartnerStore.shared.storefront()
        } catch {
            // A 404 here is normal for anyone who doesn't run a restaurant.
            merchantStorefront = nil
        }
    }

    /// The GojoDelivery header chip. Opens the sheet and refreshes behind it, so
    /// a stale status never greets the owner.
    func openMerchantPartner() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showMerchantPartner = true
        Task { await refreshMerchantPartner() }
    }

    // MARK: The restaurant

    /// Open or close for orders. Optimistic, because the toggle *is* the
    /// feedback — and it puts itself back if the server refuses (an empty menu,
    /// or a suspension), saying why.
    func setMerchantOpen(_ open: Bool) {
        guard var storefront = merchantStorefront else { return }
        let previous = storefront.isOpen
        storefront.isOpen = open
        merchantStorefront = storefront
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            do {
                merchantStorefront = try await PartnerStore.shared.setOpen(open)
            } catch {
                if var reverted = merchantStorefront {
                    reverted.isOpen = previous
                    merchantStorefront = reverted
                }
                showMerchantNotice(Self.message(from: error,
                                                fallback: open ? "Couldn't open your restaurant."
                                                               : "Couldn't close your restaurant."))
            }
        }
    }

    func saveMerchantStorefront(_ body: UpdateMerchantBody) async -> Bool {
        merchantBusy = true
        defer { merchantBusy = false }
        do {
            merchantStorefront = try await PartnerStore.shared.updateStorefront(body)
            // The catalog just changed under everyone, this user included.
            await refreshDelivery()
            return true
        } catch {
            showMerchantNotice(Self.message(from: error, fallback: "Couldn't save your changes."))
            return false
        }
    }

    // MARK: The menu
    //
    // Every mutation answers with the whole restaurant, so these just adopt the
    // server's version. No optimism: a menu editor that shows a dish which
    // didn't save is how a customer orders something that doesn't exist.

    func addMerchantSection(named name: String) {
        let clean = name.trimmed
        guard !clean.isEmpty else { return }
        runMerchantMenu("Couldn't add that section.") {
            try await PartnerStore.shared.addSection(named: clean)
        }
    }

    func renameMerchantSection(_ sectionID: UUID, to name: String) {
        let clean = name.trimmed
        guard !clean.isEmpty else { return }
        runMerchantMenu("Couldn't rename that section.") {
            try await PartnerStore.shared.renameSection(sectionID, to: clean)
        }
    }

    func deleteMerchantSection(_ sectionID: UUID) {
        runMerchantMenu("Couldn't delete that section.") {
            try await PartnerStore.shared.deleteSection(sectionID)
        }
    }

    func saveMerchantItem(sectionID: UUID, itemID: UUID?, _ body: MenuItemBody) {
        runMerchantMenu("Couldn't save that dish.") {
            if let itemID {
                return try await PartnerStore.shared.updateItem(itemID, body)
            }
            return try await PartnerStore.shared.addItem(to: sectionID, body)
        }
    }

    /// One tap: sold out, or back on. The dish carries everything else, so this
    /// is a full save with one field flipped.
    func setMerchantItemAvailable(_ item: MerchantMenuItem, _ available: Bool) {
        let body = MenuItemBody(name: item.name, detail: item.detail, priceCents: item.priceCents,
                                imageUrl: item.imageURL, popular: item.isPopular,
                                available: available, sectionId: nil)
        runMerchantMenu(available ? "Couldn't put that back on the menu."
                                  : "Couldn't mark that sold out.") {
            try await PartnerStore.shared.updateItem(item.id, body)
        }
    }

    func deleteMerchantItem(_ itemID: UUID) {
        runMerchantMenu("Couldn't delete that dish.") {
            try await PartnerStore.shared.deleteItem(itemID)
        }
    }

    /// Runs a menu mutation, adopts the restaurant it returns, and refreshes the
    /// customer catalog — the owner is looking at the same app the buyers are.
    private func runMerchantMenu(_ fallback: String,
                                 _ work: @escaping () async throws -> MerchantStorefront) {
        merchantBusy = true
        Task {
            defer { merchantBusy = false }
            do {
                let wasOpen = merchantStorefront?.isOpen
                let updated = try await work()
                withAnimation(.ggSnappy) { merchantStorefront = updated }
                // The server closes a restaurant whose last orderable dish went.
                if wasOpen == true && !updated.isOpen {
                    showMerchantNotice("Your restaurant closed — nothing on the menu is available.")
                }
                await refreshDelivery()
            } catch {
                showMerchantNotice(Self.message(from: error, fallback: fallback))
            }
        }
    }

    // MARK: Notices

    /// The merchant sheet covers GojoDelivery, so it needs its own notice —
    /// `deliveryNotice` would render behind it (the lesson from the seller-shelf
    /// pass, where a refused edit failed silently).
    func showMerchantNotice(_ message: String) {
        merchantNoticeTask?.cancel()
        withAnimation(.ggSnappy) { merchantNotice = message }
        merchantNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.ggSnappy) { self?.merchantNotice = nil }
        }
    }

    func dismissMerchantNotice() {
        merchantNoticeTask?.cancel()
        withAnimation(.ggSnappy) { merchantNotice = nil }
    }
}

// MARK: - The restaurant's money (Phase 2e M3)
//
// A merchant is a payee: an order settles into its balance, less the platform's
// commission, and Stripe Connect is the way out to a bank. All of it hangs off
// delivery's own `/mine` surface rather than the payments module's, because only
// the module that owns the merchant can prove the caller owns it.

extension AppState {

    func refreshMerchantWallet() async {
        guard backendConnected, merchantStorefront != nil else { return }
        do {
            merchantWallet = try await DeliveryStore.shared.merchantWallet()
        } catch {
            #if DEBUG
            print("Merchant wallet refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Opens Stripe's hosted onboarding. The link is single-use, so it is minted
    /// each time rather than stored — and the bank details it asks for go to
    /// Stripe, never through this app.
    func startPayoutOnboarding() {
        guard !merchantBusy else { return }
        merchantBusy = true
        Task {
            defer { merchantBusy = false }
            do {
                let link = try await DeliveryStore.shared.payoutOnboardingLink()
                guard let url = URL(string: link) else {
                    showMerchantNotice("Couldn't open the payout setup page.")
                    return
                }
                _ = await CheckoutSession().present(url)
                // Whatever they did over there, the answer is on the server.
                await refreshMerchantWallet()
            } catch {
                showMerchantNotice(Self.message(from: error,
                                                fallback: "Couldn't start payout setup."))
            }
        }
    }

    func requestPayout(_ amountMinor: Int) {
        guard !merchantBusy else { return }
        merchantBusy = true
        Task {
            defer { merchantBusy = false }
            do {
                let payout = try await DeliveryStore.shared.payOut(amountMinor: amountMinor)
                await refreshMerchantWallet()
                // A failed payout is reported rather than hidden: the money has
                // already been put back, and the owner needs to know why.
                showMerchantNotice(payout.status == "SENT"
                    ? "\(WalletStore.money(payout.amountMinor, currency: payout.currency)) is on its way to your bank."
                    : (payout.failureReason.isEmpty ? "That payout didn't go through."
                                                    : payout.failureReason))
            } catch {
                showMerchantNotice(Self.message(from: error, fallback: "Couldn't pay that out."))
            }
        }
    }
}
