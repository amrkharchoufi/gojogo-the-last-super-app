import Foundation

/// The rate table, fetched once and kept.
///
/// Deliberately not an `ObservableObject` and deliberately not on `AppState`:
/// nothing on screen should re-render because a rate moved by a thousandth, and
/// a price that flickers while somebody is reading it is worse than one that is
/// a few hours stale. It loads when the app connects, answers synchronously
/// afterwards, and every figure built on it is drawn with a `≈`.
///
/// Failure is silence. With no rates, `Money.approx` returns nil and every
/// screen shows the platform amount — which is the true one — instead of an
/// error where a price should be.
@MainActor
final class ExchangeRates {

    static let shared = ExchangeRates()

    private(set) var base = "USD"
    /// Currency code to units-per-one-base. `Decimal`, not `Double`: these get
    /// multiplied by amounts that end up next to a currency symbol, and binary
    /// floating point is how 16 300 IDR becomes 16 299,999.
    private(set) var rates: [String: Decimal] = [:]
    private(set) var asOf: Date?

    private var loaded = false

    /// Safe to call on every connect — it fetches once per launch. Rates move
    /// slowly and none of this settles anything, so re-asking on each foreground
    /// would be traffic in exchange for a digit nobody reads.
    func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        do {
            let dto: RatesDTO = try await APIClient.shared.get("/v1/payments/rates")
            base = dto.base.uppercased()
            rates = dto.rates.reduce(into: [:]) { table, entry in
                // A rate that won't parse, or isn't positive, is dropped rather
                // than defaulted. Zero would render every price as nothing.
                guard let value = Decimal(string: entry.value), value > 0 else { return }
                table[entry.key.uppercased()] = value
            }
            asOf = dto.asOf.flatMap { BackendDate.parse($0) }
        } catch {
            // Left empty on purpose: see the type comment. A screen with no rate
            // shows the amount that is actually true.
            loaded = false
            #if DEBUG
            print("Exchange rates unavailable: \(error.localizedDescription)")
            #endif
        }
    }

    /// Units of `to` per one unit of `base`, or nil when we can't say.
    ///
    /// Only converts *from* the platform currency, which is the only base the
    /// server quotes. Asked for anything else it says nothing rather than
    /// triangulating through two rates and compounding the error on a number
    /// somebody is about to read as a price.
    func rate(base from: String, to: String) -> Decimal? {
        let source = from.uppercased()
        let target = to.uppercased()
        if source == target { return 1 }
        guard source == base else { return nil }
        return rates[target]
    }
}

struct RatesDTO: Decodable {
    let base: String
    let rates: [String: String]
    let asOf: String?
    let live: Bool?
}
