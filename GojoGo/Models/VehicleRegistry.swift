import Foundation

/// What a vehicle's papers are called and what its plate looks like, wherever the
/// person filling the form in happens to be.
///
/// The partner flow was written for one country. Its plate field showed
/// `12345 - أ - 6`, its "Registered in" field showed `Casablanca`, and its
/// registration tile said *carte grise* — three answers that are correct in
/// Morocco and wrong in most of the world. This is the table that replaces the
/// assumption, and the shape of it matters more than the contents:
///
///   - **Country is asked, never guessed.** The device's region is a *default*,
///     because somebody who moved is still holding a licence from where they
///     came from, and a plate is a fact about the car rather than about the
///     phone photographing it.
///   - **A subdivision is asked only where the plate has one.** In the United
///     States, Canada, Australia, India, Brazil, Mexico, Nigeria, the Emirates,
///     South Africa and Pakistan a plate really is issued by a state or a
///     province, and Texas ABC-1234 is not California ABC-1234. Almost
///     everywhere else plates are national, and asking for a city there is both
///     noise and a way to let a duplicate through — two people typing
///     "Casablanca" and "Casa" would land in different uniqueness scopes for the
///     same car.
///   - **The default is neutral, not Moroccan.** A country nobody has written a
///     row for gets a generic plate hint and the words "vehicle registration",
///     which is a worse experience than a local one and a much better one than
///     being asked for a document that doesn't exist where you live.
enum VehicleRegistry {

    /// One country as the picker shows it — code for the wire, name for the eye.
    struct Country: Identifiable, Hashable {
        let code: String
        let name: String
        var id: String { code }
    }

    /// How this country's registration works, as far as the form needs to know.
    struct Rules {
        /// What the issuing state or province is called, or nil where plates are
        /// national and there is nothing to ask.
        let subdivisionLabel: String?
        /// One of them, for the placeholder — "Texas" says what "State" means
        /// faster than any label does.
        let subdivisionExample: String?
        /// A plate written the way one is written here, for the placeholder.
        let plateExample: String
        /// What the registration certificate is called locally. "Carte grise" in
        /// Morocco, "V5C" in Britain — a driver looking for the right piece of
        /// paper should read the name they know it by.
        let registrationName: String

        var asksForSubdivision: Bool { subdivisionLabel != nil }
    }

    // MARK: The countries

    /// Every ISO region with a name in the reader's language, sorted the way
    /// their language sorts. Taken from the system rather than typed out here:
    /// a hand-written list of "the countries we support" is the same assumption
    /// this file exists to delete, and it goes stale the first time a border
    /// moves.
    static let countries: [Country] = {
        Locale.Region.isoRegions
            .filter { $0.identifier.count == 2 }
            .compactMap { region in
                guard let name = Locale.current.localizedString(forRegionCode: region.identifier)
                else { return nil }
                return Country(code: region.identifier, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    static func name(of code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    /// Where the phone thinks it is — a starting point for the picker, never an
    /// answer. Empty when the device won't say, in which case the driver picks.
    static var deviceCountry: String {
        Locale.current.region?.identifier ?? ""
    }

    static func flag(_ code: String) -> String {
        guard code.count == 2 else { return "" }
        return String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127_397 + $0.value)
        }))
    }

    // MARK: The rules

    static func rules(for code: String) -> Rules {
        let subdivision = subdivisions[code]
        return Rules(subdivisionLabel: subdivision?.label,
                     subdivisionExample: subdivision?.example,
                     plateExample: plateExamples[code] ?? "AB 123 CD",
                     registrationName: registrationNames[code] ?? "vehicle registration")
    }

    /// The countries where a plate is issued by a state or a province rather
    /// than nationally — so the subdivision is part of which car this is, not a
    /// nice-to-know address.
    private static let subdivisions: [String: (label: String, example: String)] = [
        "US": ("State", "Texas"),
        "CA": ("Province", "Ontario"),
        "AU": ("State or territory", "Victoria"),
        "IN": ("State", "Maharashtra"),
        "BR": ("State", "São Paulo"),
        "MX": ("State", "Jalisco"),
        "NG": ("State", "Lagos"),
        "AE": ("Emirate", "Dubai"),
        "ZA": ("Province", "Western Cape"),
        "PK": ("Province", "Punjab"),
    ]

    /// Not validation — a hint. Plate formats change, old plates stay legal for
    /// decades, and refusing a real car because its plate doesn't match a
    /// pattern somebody wrote down is a worse failure than accepting an odd one
    /// and letting a reviewer look at the photograph.
    private static let plateExamples: [String: String] = [
        "MA": "12345 - أ - 6",  "DZ": "12345-116-16", "TN": "123 TU 4567",
        "EG": "ABC 123",        "SN": "AA-123-BB",    "CI": "1234 AB 01",
        "NG": "ABC-123-DE",     "KE": "KAA 123A",     "GH": "GR 1234-20",
        "ZA": "CA 123-456",     "CM": "LT 123 AB",    "ML": "AB 1234 MB",
        "FR": "AB-123-CD",      "ES": "1234 ABC",     "PT": "AA-00-BB",
        "IT": "AB 123 CD",      "DE": "B-AB 1234",    "NL": "12-ABC-3",
        "BE": "1-ABC-123",      "GB": "AB12 CDE",     "IE": "12-D-12345",
        "PL": "WA 12345",       "TR": "34 ABC 123",   "GR": "ABC-1234",
        "US": "7ABC123",        "CA": "ABCD 123",     "MX": "ABC-12-34",
        "BR": "ABC1D23",        "AR": "AB 123 CD",    "CO": "ABC123",
        "AE": "A 12345",        "SA": "ABC 1234",     "QA": "123456",
        "IN": "MH 12 AB 1234",  "PK": "ABC-123",      "ID": "B 1234 ABC",
        "AU": "ABC-123",        "NZ": "ABC123",       "JP": "品川 500 あ 12-34",
    ]

    /// The name on the document, in the words a driver here would use for it.
    /// Every one of these is a real piece of paper somebody has to go and find
    /// in a drawer, and "vehicle registration" sends a French speaker looking
    /// for the wrong thing.
    private static let registrationNames: [String: String] = [
        "MA": "carte grise", "FR": "carte grise", "BE": "carte grise",
        "LU": "carte grise", "DZ": "carte grise", "TN": "carte grise",
        "SN": "carte grise", "CI": "carte grise", "CM": "carte grise",
        "ML": "carte grise", "NE": "carte grise", "BF": "carte grise",
        "GA": "carte grise", "CD": "carte grise", "MG": "carte grise",
        "GB": "V5C log book",
        "DE": "Fahrzeugschein",
        "NL": "kentekenbewijs",
        "ES": "permiso de circulación",
        "IT": "carta di circolazione",
        "PT": "documento único automóvel",
        "BR": "CRLV",
        "MX": "tarjeta de circulación",
        "AR": "cédula verde",
        "EG": "رخصة السيارة",
    ]
}
