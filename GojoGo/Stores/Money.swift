import Foundation

/// Money on screen: the exact amount, and roughly what that is where you live.
///
/// Two jobs that look like one and are not.
///
/// **Formatting.** Every amount on the wire is integer minor units in the
/// platform's single currency. Turning 3000 into something readable used to be
/// `"$" + String(format: "%.2f", …)`, which is right in exactly one place: it
/// puts the symbol on the wrong side for half of Europe, uses a full stop where
/// a comma belongs, groups nothing, and renders ¥1,500 as "JPY 15.00" because it
/// assumes every currency divides by a hundred. Yen and won don't divide at all;
/// the Tunisian dinar divides by a thousand.
///
/// **Conversion.** A driver in Casablanca reading "$30" has to stop and work out
/// whether that is a coffee or a week's shopping. So an amount can also be shown
/// as *approximately* what it is worth in the currency their phone is set to,
/// from rates the server serves and refreshes.
///
/// The line between the two is the important part, and it is drawn in one place:
/// **`exact` is what will be charged; `approx` is a translation.** The ledger is
/// single-currency by design — a stake is 3000 minor units of the platform
/// currency whoever is looking — so a converted figure is never the number
/// somebody is billed, never the number in their wallet, and never appears
/// without the `≈` that says so. Anywhere money actually moves, the exact amount
/// is shown too, and shown first. A number you will be charged and a number to
/// help you understand it are different things; a customer arguing with their
/// card statement is what conflating them costs.
@MainActor
enum Money {

    // MARK: The exact amount

    /// The amount as it will actually be charged, formatted for the reader.
    ///
    /// Their locale decides the shape — separators, grouping, which side the
    /// symbol goes on — while `currency` decides the symbol and how far the
    /// amount divides. A French reader looking at a dollar price should see it
    /// written the French way and still see dollars.
    static func exact(_ minor: Int, currency: String = "USD") -> String {
        let code = normalised(currency)
        let major = major(minor, code)
        return formatter(for: code).string(from: major as NSDecimalNumber)
            ?? "\(code) \(major)"
    }

    // MARK: Roughly, in your money

    /// The same amount in the reader's own currency, marked approximate.
    ///
    /// `nil` — meaning "say nothing" — in the three cases where a second figure
    /// would be noise or a lie: when it is already their currency, when the
    /// device won't say what that is, and when the server has no rate for it. A
    /// missing rate is a real answer; inventing 1:1 to have something to draw
    /// would misprice the screen by whatever the true rate happens to be.
    static func approx(_ minor: Int, currency: String = "USD") -> String? {
        guard let converted = converted(minor, from: currency) else { return nil }
        return "≈ " + converted
    }

    /// Both, for a single line where money moves: the charge, then the
    /// translation. "$30.00 · ≈ 298,50 MAD" — in that order, because the first
    /// one is what will appear on a statement.
    static func exactWithApprox(_ minor: Int, currency: String = "USD") -> String {
        let charged = exact(minor, currency: currency)
        guard let local = approx(minor, currency: currency) else { return charged }
        return "\(charged) · \(local)"
    }

    /// What the reader's phone says their money is. Empty when it won't say.
    static var deviceCurrency: String {
        Locale.current.currency?.identifier.uppercased() ?? ""
    }

    /// Whether a conversion is available at all — for a view deciding whether to
    /// make room for a second line before it has an amount to put there.
    static func canConvert(from currency: String = "USD") -> Bool {
        converted(100, from: currency) != nil
    }

    private static func converted(_ minor: Int, from currency: String) -> String? {
        let base = normalised(currency)
        let target = deviceCurrency
        guard !target.isEmpty, target != base,
              let rate = ExchangeRates.shared.rate(base: base, to: target) else { return nil }
        let value = major(minor, base) * rate
        return formatter(for: target).string(from: value as NSDecimalNumber)
            ?? "\(target) \(value)"
    }

    // MARK: Minor units

    /// How far a currency divides.
    ///
    /// Not asked of the formatter, which is only reliable about the locale's own
    /// currency, and not assumed to be two — assuming two is what turns ¥1,500
    /// into "15.00". The exceptions are a short closed list in ISO 4217 and
    /// worth naming: three of the zero-decimal ones (XOF, XAF, VND) are markets
    /// this platform has rates for, so getting it wrong would be a hundredfold
    /// error on a live screen rather than a hypothetical one.
    private static let zeroDecimal: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG",
        "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF",
    ]

    private static let threeDecimal: Set<String> = [
        "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND",
    ]

    static func minorUnits(_ currency: String) -> Int {
        let code = normalised(currency)
        if zeroDecimal.contains(code) { return 0 }
        if threeDecimal.contains(code) { return 3 }
        return 2
    }

    private static func major(_ minor: Int, _ code: String) -> Decimal {
        Decimal(minor) / powerOfTen(minorUnits(code))
    }

    private static func powerOfTen(_ exponent: Int) -> Decimal {
        var result = Decimal(1)
        for _ in 0..<max(0, exponent) { result *= 10 }
        return result
    }

    private static func normalised(_ currency: String) -> String {
        let trimmed = currency.trimmingCharacters(in: .whitespaces).uppercased()
        return trimmed.isEmpty ? "USD" : trimmed
    }

    // MARK: Formatters

    /// One per currency, kept because building an `NumberFormatter` is not cheap
    /// and a statement builds one line per row.
    private static var formatters: [String: NumberFormatter] = [:]

    private static func formatter(for code: String) -> NumberFormatter {
        if let existing = formatters[code] { return existing }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        // The reader's locale for the *shape*, the code for the *symbol* — so a
        // dollar price reads "30,00 $US" to a French speaker rather than being
        // silently redenominated into euros.
        formatter.locale = Locale.current
        formatter.usesGroupingSeparator = true
        // Set explicitly for the same reason `minorUnits` exists: left to itself
        // the formatter takes its fraction digits from the locale's currency,
        // not from the one it has been told to render.
        let digits = minorUnits(code)
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        formatters[code] = formatter
        return formatter
    }
}
