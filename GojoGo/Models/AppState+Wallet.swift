import SwiftUI

// MARK: - GoJo Wallet (Phase 2e M3)
//
// The wallet is the app's only source of money. A delivery order holds against
// it at checkout and settles when the food arrives; Phase 3's stake and tokens
// land in the same balance. Topping up leaves the app entirely — a
// Stripe-hosted page in a system sheet — which is why there is no card form
// anywhere in this codebase and never should be.

extension AppState {

    var walletBalanceLabel: String {
        WalletStore.money(wallet?.availableMinor ?? 0, currency: wallet?.currency ?? "USD")
    }

    /// Whether a card top-up can be started at all. False on an environment
    /// with no Stripe credentials, where the button is hidden rather than
    /// offered and then refused.
    var walletTopUpAvailable: Bool { wallet?.topUpEnabled ?? false }

    func refreshWallet() async {
        guard backendConnected else { return }
        do {
            async let balances = WalletStore.shared.wallet()
            async let history = WalletStore.shared.transactions()
            wallet = try await balances
            walletTransactions = try await history
        } catch {
            #if DEBUG
            print("Wallet refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Runs a card top-up end to end: ask the server for a hosted page, present
    /// it, then ask the server what happened.
    ///
    /// The last step is the important one. Coming back from the page means the
    /// customer's browser reached a URL — the wallet is credited by Stripe's
    /// signed webhook, which usually lands first but is not promised to. So the
    /// app reconciles explicitly, and if the money still hasn't arrived it says
    /// so rather than showing a stale balance as though nothing happened.
    func topUpWallet(amountMinor: Int) {
        guard !walletBusy else { return }
        walletBusy = true
        Task {
            defer { walletBusy = false }
            do {
                let topUp = try await WalletStore.shared.startTopUp(amountMinor: amountMinor)
                guard let url = URL(string: topUp.checkoutUrl) else {
                    showWalletNotice("Couldn't open the payment page.")
                    return
                }
                let outcome = await CheckoutSession().present(url)
                // Re-check on a cancel too: dismissing the sheet after paying is
                // an easy thing to do, and the payment is real either way.
                let status = try? await WalletStore.shared.refreshTopUp(topUp.id)
                await refreshWallet()

                switch status?.status {
                case "SUCCEEDED":
                    showWalletNotice("Added \(WalletStore.money(topUp.amountMinor, currency: topUp.currency)) to your wallet.")
                case "CREATED" where outcome == .returned:
                    showWalletNotice("Payment received — your balance will update in a moment.")
                default:
                    if outcome == .returned {
                        showWalletNotice("That payment didn't go through.")
                    }
                }
            } catch {
                showWalletNotice(Self.message(from: error,
                                              fallback: "Couldn't start that top-up."))
            }
        }
    }

    func showWalletNotice(_ message: String) {
        walletNoticeTask?.cancel()
        walletNotice = message
        walletNoticeTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { walletNotice = nil }
        }
    }
}
