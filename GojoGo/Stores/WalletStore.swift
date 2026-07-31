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

    static func money(_ minor: Int, currency: String = "USD") -> String {
        let symbol = currency == "USD" ? "$" : "\(currency) "
        let sign = minor < 0 ? "−" : ""
        return "\(sign)\(symbol)\(String(format: "%.2f", Double(abs(minor)) / 100))"
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
        case "REWARD":      return "Reward"
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
}

/// Signed from the reader's point of view — negative means money left.
struct WalletTransactionDTO: Decodable, Identifiable {
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
