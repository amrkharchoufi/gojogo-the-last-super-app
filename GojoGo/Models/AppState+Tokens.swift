import SwiftUI

// MARK: - Ride tokens (Phase 3 M4)
//
// The platform's revenue on a ride. The driver keeps every cent of the fare —
// rides carry no commission — and pays a token to accept the job.
//
// The thing this file exists for is the *silence*. A driver who cannot pay is
// filtered out of dispatch's candidate search, which is exactly right and
// completely invisible: no error, no refusal, no offer. Without a screen that
// says "you're out of tokens", a driver goes online, waits, and concludes the
// app is broken. So the server sends the sentence and this shows it.
//
// Two endpoints, in two modules, and the split is the server's: `payments`
// sells tokens (it knows what one is worth), `travel` says what they buy (it
// knows what a ride costs). The app asks both and never does the arithmetic.

extension AppState {

    /// Tokens held, from whichever read landed most recently.
    var tokenBalance: Int { rideTokens?.balance ?? tokenWallet?.tokens ?? 0 }

    /// Why no work is arriving, when that's the reason. Nil when they can work.
    var tokenRefusal: String? { rideTokens?.refusal }

    /// Worth drawing attention to — either they've stopped being offered trips
    /// or they're about to.
    var tokensNeedAttention: Bool {
        rideTokens?.canWork == false || tokenWallet?.isLow == true
    }

    // MARK: Reading

    /// Both halves at once. Only for a registered driver: a token balance on
    /// the screen of somebody who has never been approved is a currency for a
    /// job they don't have.
    func refreshTokens() async {
        guard backendConnected, isDispatchRegistered else { return }
        async let shelf = try? WalletStore.shared.tokens()
        async let prices = try? TravelStore.shared.tokens()
        let (loadedShelf, loadedPrices) = await (shelf, prices)
        if let loadedShelf { tokenWallet = loadedShelf }
        if let loadedPrices { rideTokens = loadedPrices }
    }

    // MARK: Buying

    /// Buys a pack out of the wallet.
    ///
    /// A short wallet is the interesting path, and it is the same one the $30
    /// stake takes: a 402 carries the shortfall, so the app offers a top-up for
    /// exactly the missing amount rather than a dead end. There is no card form
    /// here for the same reason there is none anywhere else in this app.
    func buyTokenPack(_ pack: TokenPackDTO) {
        guard !tokensBusy else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        tokensBusy = true
        Task {
            defer { tokensBusy = false }
            do {
                tokenWallet = try await WalletStore.shared.purchaseTokens(packId: pack.id)
                rideTokens = try? await TravelStore.shared.tokens()
                await refreshWallet()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showWalletNotice("\(pack.tokens) tokens added.")
            } catch APIClient.APIError.http(let status, let message) where status == 402 {
                let shortfall = max(0, pack.priceMinor - (tokenWallet?.availableMinor ?? 0))
                pendingTokenTopUpMinor = shortfall > 0 ? shortfall : pack.priceMinor
                showWalletNotice(message ?? "Your wallet is short "
                    + WalletStore.money(pendingTokenTopUpMinor ?? 0) + ".")
            } catch {
                showWalletNotice(Self.message(from: error,
                                              fallback: "Couldn't buy those tokens."))
            }
        }
    }

    /// Tops the wallet up by exactly what the pack was short, then leaves the
    /// driver on the same screen to tap buy again. One tap, because two ("go
    /// and top up, then come back") is where people leave.
    func topUpForTokens() {
        guard let amount = pendingTokenTopUpMinor, amount > 0 else { return }
        pendingTokenTopUpMinor = nil
        topUpWallet(amountMinor: amount)
    }
}
