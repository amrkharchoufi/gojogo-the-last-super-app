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

    /// Minor units to something a person reads.
    ///
    /// What this replaced was `"$" + two decimal places`, which is right for
    /// exactly one currency in exactly one place. Two things were wrong with it,
    /// and only one of them is cosmetic.
    ///
    /// The cosmetic one: it hardcoded the symbol before the number with a full
    /// stop and no grouping, so a French or German reader got the separator and
    /// the symbol position their language doesn't use, and 1234567 read as
    /// "$12345.67". The system knows how every locale writes money; we don't.
    ///
    /// The one that mattered: **it assumed every currency divides by a hundred.**
    /// The yen doesn't divide at all — ¥1,500 is 1500 minor units, and the old
    /// code showed it as "JPY 15.00", a hundredfold error. So do the West
    /// African and Central African CFA francs, the Vietnamese dong, the Korean
    /// won and the Chilean peso. In the other direction the Tunisian, Kuwaiti,
    /// Bahraini, Jordanian, Omani, Iraqi and Libyan dinars divide by a thousand,
    /// and 1500 of those is 1.500, not 15.00.
    ///
    /// Both exception lists are short and closed, so they are written down here
    /// rather than guessed at. Nothing renders a non-USD amount today, which is
    /// the only reason this was survivable; it stops being survivable the moment
    /// `platform.currency` is set to anything else.
    static func money(_ minor: Int, currency: String = "USD") -> String {
        let code = normalised(currency)
        let digits = minorUnits(code)
        let major = Decimal(minor) / powerOfTen(digits)
        return formatter(for: code, digits: digits).string(from: major as NSDecimalNumber)
            ?? "\(code) \(major)"
    }

    /// How far a currency divides — the ISO 4217 exponent.
    ///
    /// Deliberately not asked of `NumberFormatter`: left to itself it takes the
    /// fraction digits from the *locale's* currency rather than the one it has
    /// been told to render, so a phone set to Japan would drop the cents off a
    /// dollar amount.
    static func minorUnits(_ currency: String) -> Int {
        let code = normalised(currency)
        if zeroDecimalCurrencies.contains(code) { return 0 }
        if threeDecimalCurrencies.contains(code) { return 3 }
        return 2
    }

    private static let zeroDecimalCurrencies: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG",
        "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF",
    ]

    private static let threeDecimalCurrencies: Set<String> = [
        "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND",
    ]

    private static func normalised(_ currency: String) -> String {
        let trimmed = currency.trimmingCharacters(in: .whitespaces).uppercased()
        return trimmed.isEmpty ? "USD" : trimmed
    }

    /// `Decimal`, not `Double`: this divides an amount that ends up next to a
    /// currency symbol, and binary floating point is how 16300 becomes 162.99999.
    private static func powerOfTen(_ exponent: Int) -> Decimal {
        var result = Decimal(1)
        for _ in 0..<max(0, exponent) { result *= 10 }
        return result
    }

    /// One per currency, kept because building a `NumberFormatter` is not cheap
    /// and a statement builds one line per row.
    private static var formatters: [String: NumberFormatter] = [:]

    private static func formatter(for code: String, digits: Int) -> NumberFormatter {
        if let existing = formatters[code] { return existing }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        // The reader's locale decides the *shape* — separators, grouping, which
        // side the symbol goes on — while the code decides the *symbol*. A
        // French reader looking at a dollar price should see it written the
        // French way and still see dollars, not be silently shown euros.
        formatter.locale = Locale.current
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        formatters[code] = formatter
        return formatter
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
