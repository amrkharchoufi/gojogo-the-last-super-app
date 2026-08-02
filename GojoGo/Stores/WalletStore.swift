import SwiftUI

/// The GoJo Wallet's API surface (Phase 2e M3).
///
/// Deliberately thin: the app never computes what anything costs or what a
/// balance should be, it reads both. Money is integer minor units on the wire
/// all the way through — the one place it becomes a decimal is
/// `Wallet.money(_:)`, where a person reads it.
@MainActor
final class WalletStore {

    static let shared = WalletStore()

    func wallet() async throws -> WalletDTO {
        try await APIClient.shared.get("/v1/payments/wallet")
    }

    func transactions(limit: Int = 50) async throws -> [WalletTransactionDTO] {
        try await APIClient.shared.get("/v1/payments/transactions?limit=\(limit)")
    }

    /// Starts a card top-up. Returns a Stripe-hosted URL to open — the card
    /// details never reach this app, which is why there is no card form in it.
    func startTopUp(amountMinor: Int) async throws -> TopUpDTO {
        try await APIClient.shared.post("/v1/payments/topups",
                                        body: TopUpBody(amountMinor: amountMinor))
    }

    /// Asks the server to check with Stripe, for the case where the webhook
    /// hasn't landed by the time the sheet closes. The same "don't depend on
    /// someone else's console being configured" fallback the KYC flow has.
    func refreshTopUp(_ id: UUID) async throws -> TopUpStatusDTO {
        try await APIClient.shared.post("/v1/payments/topups/\(id)/refresh")
    }

    // MARK: Ride tokens (Phase 3 M4)

    /// The token shelf: what the caller holds, and what is on sale.
    func tokens() async throws -> TokenWalletDTO {
        try await APIClient.shared.get("/v1/payments/tokens")
    }

    /// Buys a pack **out of the wallet**, not off a card. Card money only ever
    /// arrives as a top-up in this app, which is why there is one Stripe flow
    /// and not two — a short wallet comes back as a 402 with the shortfall.
    func purchaseTokens(packId: UUID) async throws -> TokenWalletDTO {
        try await APIClient.shared.post("/v1/payments/tokens/purchase",
                                        body: TokenPurchaseBody(packId: packId))
    }

    /// The exact amount, formatted for whoever is reading it.
    ///
    /// Kept as the name three dozen call sites already use; the work moved to
    /// `Money`. What it used to do was `"$" + String(format: "%.2f", …)`, which
    /// is correct in one locale and one currency: it put the symbol on the wrong
    /// side for half of Europe, used a full stop where a comma belongs, grouped
    /// nothing, and rendered ¥1,500 as "JPY 15.00" because it assumed two
    /// decimal places everywhere. Yen has none; the Kuwaiti dinar has three.
    ///
    /// For a second line reading "≈ 298,50 MAD", ask `Money.approx` — but read
    /// what it says about when a converted figure may be shown first.
    static func money(_ minor: Int, currency: String = "USD") -> String {
        Money.exact(minor, currency: currency)
    }

    /// A line on the statement, in words. The ledger's kinds are precise; a
    /// person reading their own history wants the plain version.
    static func describe(_ transaction: WalletTransactionDTO) -> String {
        if !transaction.memo.isEmpty { return transaction.memo }
        switch transaction.kind {
        case "TOPUP":       return "Wallet top-up"
        case "HOLD":        return "Held for an order"
        case "RELEASE":     return "Released back"
        case "CAPTURE":     return "Order paid"
        case "FEE":         return "Service fee"
        case "TIP":         return "Tip"
        case "REFUND":      return "Refund"
        case "PAYOUT":      return "Payout"
        case "REWARD":          return "Reward"
        case "TOKEN_PURCHASE":  return "Ride tokens"
        case "TOKEN_SPEND":     return "Token spent on a trip"
        default:            return transaction.kind.capitalized
        }
    }
}

// MARK: - Wire shapes

struct WalletDTO: Decodable {
    let currency: String
    let availableMinor: Int
    let escrowMinor: Int
    let stakingMinor: Int
    let tokensMinor: Int
    let rewardsMinor: Int
    /// False on an environment with no Stripe keys or no webhook secret. The
    /// app hides the top-up button rather than offering one that 503s.
    let topUpEnabled: Bool
    let publishableKey: String
    let topUpMinMinor: Int
    let topUpMaxMinor: Int
    /// What the TOKENS bucket divides by, so this screen can say "12 tokens"
    /// without a second call or a constant of its own.
    let minorPerToken: Int

    /// Whole tokens only: a part-token cannot buy a ride, so showing it would
    /// be a number that never becomes one.
    var tokenCount: Int { minorPerToken > 0 ? tokensMinor / minorPerToken : 0 }
}

/// A quantity of tokens at a price. `bonusTokens` is the platform's share of
/// the pack — a discount that is funded rather than invented.
struct TokenPackDTO: Decodable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let tokens: Int
    let priceMinor: Int
    let bonusTokens: Int
    let note: String
}

struct TokenWalletDTO: Decodable, Equatable {
    let tokens: Int
    let tokensMinor: Int
    let minorPerToken: Int
    /// Spendable wallet — a pack is bought out of it, so the screen knows
    /// before it offers.
    let availableMinor: Int
    let currency: String
    let lowThreshold: Int
    let packs: [TokenPackDTO]
    /// The token half of the statement. A driver looking at tokens wants token
    /// lines, not their lunch.
    let movements: [WalletTransactionDTO]

    var isLow: Bool { tokens <= lowThreshold }
}

struct TokenPurchaseBody: Encodable {
    let packId: UUID
}

/// Signed from the reader's point of view — negative means money left.
struct WalletTransactionDTO: Decodable, Equatable, Identifiable {
    let id: UUID
    let amountMinor: Int
    let currency: String
    let kind: String
    let refKind: String
    let refId: UUID?
    let memo: String
    let createdAt: String
}

struct TopUpBody: Encodable {
    let amountMinor: Int
}

struct TopUpDTO: Decodable {
    let id: UUID
    let checkoutUrl: String
    let amountMinor: Int
    let currency: String
}

struct TopUpStatusDTO: Decodable {
    let id: UUID
    let amountMinor: Int
    let currency: String
    /// CREATED / SUCCEEDED / FAILED / EXPIRED.
    let status: String
    let checkoutUrl: String?
    let createdAt: String
}
