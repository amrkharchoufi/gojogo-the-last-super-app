import Foundation

// MARK: - Delivery module DTOs (Phase 2b · Milestone 4)
//
// Mirror the backend `delivery` records. Money is integer cents; the store maps
// it to the `Double` the SwiftUI delivery models were written against.

struct MenuItemDTO: Decodable {
    let id: UUID
    let name: String
    let detail: String
    let priceCents: Int
    let imageUrl: String?
    let popular: Bool
}

struct MenuSectionDTO: Decodable {
    let id: UUID
    let name: String
    let items: [MenuItemDTO]
}

struct MerchantDTO: Decodable {
    let id: UUID
    let name: String
    let cuisine: String
    let rating: Double
    let reviewCount: Int
    let etaMinutes: Int
    let deliveryFeeCents: Int
    let imageUrl: String?
    let promo: String?
    let tags: [String]
    let categories: [String]
    let latitude: Double
    let longitude: Double
    /// Empty in browse results; filled by the detail endpoint.
    let menu: [MenuSectionDTO]
    /// The owner's arrangement of the page above the menu (SPECS §9). Detail
    /// only, like the menu, and optional-decoded like every field added after a
    /// release — a backend that predates this milestone simply omits it.
    let storefront: StorefrontDTO?
}

struct OrderMerchantDTO: Decodable {
    let id: UUID
    let name: String
    let imageUrl: String?
    let latitude: Double
    let longitude: Double
}

/// Whoever is bringing the food. A real person out of the dispatch registry
/// since Phase 4 M1 rather than one of four hardcoded names — which is why it
/// has a position, reported by their phone and present only while they are
/// actually carrying this order.
struct CourierDTO: Decodable {
    let name: String
    let vehicle: String
    let rating: Double
    let deliveries: Int
    let latitude: Double?
    let longitude: Double?
    /// A `String`, not a `Date`: the shared decoder has no date strategy, so a
    /// `Date` here would fail the moment a courier actually reported a position.
    let positionAt: String?

    var positionAtDate: Date? { positionAt.flatMap { BackendDate.parse($0) } }
}

struct OrderLineDTO: Decodable {
    let menuItemId: UUID
    let name: String
    let unitPriceCents: Int
    let qty: Int
}

struct DeliveryAddressDTO: Decodable {
    let id: UUID
    let label: String
    let line1: String
    let note: String
    let latitude: Double?
    let longitude: Double?
    let isDefault: Bool
}

/// Where an order went — a copy taken at order time, so editing the saved
/// address later doesn't rewrite the receipt.
struct OrderAddressDTO: Decodable {
    let id: UUID?
    let label: String
    let line1: String
    let note: String
    let latitude: Double?
    let longitude: Double?
}

struct SaveAddressBody: Encodable {
    let label: String
    let line1: String
    let note: String
    let latitude: Double?
    let longitude: Double?
    let makeDefault: Bool
}

/// A placed order. `status`, `etaMinutes` and `courierProgress` are the
/// server's view of fulfilment — the app renders them rather than running its
/// own timer, so two devices (or a reinstall) agree on the same delivery.
struct OrderDTO: Decodable {
    let id: UUID
    let merchant: OrderMerchantDTO
    let status: String
    let etaMinutes: Int
    let courierProgress: Double
    let courier: CourierDTO?
    /// NONE / SEARCHING / ASSIGNED / FAILED (Phase 4 M1). The only way the app
    /// learns that the kitchen is cooking and nobody has taken the delivery yet
    /// — which is not a stage of an order, and so deliberately not a seventh
    /// `status`.
    let courierSearch: String?
    /// Why it ended, when it ended badly. "Cancelled" on its own leaves someone
    /// wondering whether they did it themselves.
    let cancelReason: String?
    /// When the kitchen says the food will be done. Null until they accept.
    let readyAt: String?
    let lines: [OrderLineDTO]
    let subtotalCents: Int
    let deliveryFeeCents: Int
    let serviceFeeCents: Int
    let totalCents: Int
    /// Optional-decoded, like every field added after a release: a backend that
    /// predates the wallet still answers this endpoint, and the app has to keep
    /// working against it.
    let discountCents: Int?
    let tipCents: Int?
    let promotionCode: String?
    /// UNPAID / HELD / CAPTURED / RELEASED / REFUNDED.
    let paymentStatus: String?
    let currency: String
    let addressLabel: String
    let address: OrderAddressDTO?
    let note: String
    let rating: Int?
    let placedAt: String
    let statusChangedAt: String
    let etaAt: String
}

/// "Nothing in flight" is a 200 with a null order, not a 404.
struct ActiveOrderDTO: Decodable {
    let order: OrderDTO?
}

struct PlaceOrderLineBody: Encodable {
    let menuItemId: UUID
    let qty: Int
}

struct PlaceOrderBody: Encodable {
    let merchantId: UUID
    let lines: [PlaceOrderLineBody]
    /// A saved address of the caller's. Nil falls back to their default one.
    let addressId: UUID?
    let note: String
    /// A code, never an amount — what a discount is worth is decided server-side.
    let promotionCode: String?
    let tipCents: Int
}

struct RateOrderBody: Encodable {
    let rating: Int
}

struct TipBody: Encodable {
    let tipCents: Int
}

// MARK: Checkout

struct QuoteBody: Encodable {
    let merchantId: UUID
    let lines: [PlaceOrderLineBody]
    let promotionCode: String?
    let tipCents: Int
}

/// What a basket costs, priced by the server before anything is charged — and
/// crucially whether the wallet covers it, so the app can offer a top-up rather
/// than walk someone into a refused checkout.
struct QuoteDTO: Decodable {
    let subtotalCents: Int
    let deliveryFeeCents: Int
    let serviceFeeCents: Int
    let discountCents: Int
    let tipCents: Int
    let totalCents: Int
    let currency: String
    let promotionCode: String
    let promotionLabel: String
    let walletAvailableMinor: Int
    let walletCovers: Bool
    let shortfallMinor: Int
}

struct DeliveryPromotionDTO: Decodable, Identifiable {
    let id: UUID
    let code: String
    let label: String
    /// PERCENT / FIXED / FREE_DELIVERY.
    let kind: String
    let valueBps: Int
    let amountCents: Int
    let minBasketCents: Int
    let maxDiscountCents: Int
    let perUserLimit: Int
    let active: Bool
}

// MARK: The merchant's side

struct MerchantWalletDTO: Decodable {
    let availableMinor: Int
    let currency: String
    let commissionBps: Int
    let payoutsConfigured: Bool
    let payoutsReady: Bool
    /// Stripe's own `requirements.currently_due` list, comma-separated and in
    /// Stripe's vocabulary. Never rendered as-is — see `payoutsNeedSentence`.
    let payoutsRequirement: String
    let payoutMinMinor: Int
    let recent: [MerchantTransactionDTO]
}

extension MerchantWalletDTO {
    /// What is still missing, said in the language of the person reading it.
    ///
    /// The server passes Stripe's field keys through verbatim — `business_type`,
    /// `tos_acceptance.ip`, `external_account`. Printed straight onto the
    /// earnings card they read as a stack trace that leaked into the product,
    /// and a restaurant owner can't act on `tos_acceptance.date` anyway: the
    /// only thing to do about any of them is the button underneath. So each key
    /// becomes the thing it actually asks for, the two halves of a terms
    /// acceptance collapse into one phrase, and anything this app doesn't
    /// recognise turns into "a few more details" rather than being shown raw.
    var payoutsNeedSentence: String {
        let needs = Self.humanNeeds(payoutsRequirement)
        guard !needs.isEmpty else { return "Stripe is still reviewing your details." }
        return "Stripe still needs \(Self.sentenceList(needs))."
    }

    private static func humanNeeds(_ raw: String) -> [String] {
        var seen: Set<String> = []
        return raw.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { Self.phrase(for: $0) }
            .filter { seen.insert($0).inserted }
    }

    /// Matched on the key's shape rather than the whole string: Stripe indexes
    /// the owner fields (`owners.0.address.line1`) and adds new leaves to the
    /// same branches, so the tail is what carries the meaning.
    private static func phrase(for key: String) -> String {
        let k = key.lowercased()
        if k.hasPrefix("tos_acceptance")         { return "you to accept Stripe's terms" }
        if k == "external_account"               { return "your bank account" }
        if k == "business_type"                  { return "whether you're a person or a company" }
        if k.hasPrefix("business_profile.url")   { return "a link to your website or page" }
        if k.hasPrefix("business_profile")       { return "a little about your business" }
        if k.contains("verification.document")   { return "a photo of your ID" }
        if k.contains("verification.additional_document") { return "one more document" }
        if k.contains("dob")                     { return "your date of birth" }
        if k.contains("id_number") || k.contains("ssn_last_4") { return "your ID number" }
        if k.contains("tax_id")                  { return "your tax ID" }
        if k.contains("address")                 { return "your address" }
        if k.contains("phone")                   { return "your phone number" }
        if k.contains("email")                   { return "your email" }
        if k.contains("first_name") || k.contains("last_name") || k.contains("name") {
            return "your legal name"
        }
        return "a few more details"
    }

    /// "a, b and c" — the list is read out loud in a sentence, not bulleted.
    private static func sentenceList(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }
}

struct MerchantTransactionDTO: Decodable, Identifiable {
    let id: UUID
    let amountMinor: Int
    let kind: String
    let memo: String
    let createdAt: String
}

struct PayoutBody: Encodable {
    let amountMinor: Int
}

struct PayoutDTO: Decodable {
    let id: UUID
    let amountMinor: Int
    let currency: String
    /// REQUESTED / SENT / FAILED — a failure is reported, not hidden.
    let status: String
    let failureReason: String
}

// MARK: The kitchen's queue (Phase 4 M1)

/// One order as its restaurant sees it. There was deliberately no such screen
/// before real couriers: a simulated timeline walked every order along, and a
/// kitchen button the job would immediately overrule is worse than no button.
struct MerchantOrderDTO: Decodable, Identifiable {
    let id: UUID
    /// CONFIRMED / PREPARING / COURIER_TO_RESTAURANT / DELIVERING / DELIVERED / CANCELLED.
    let status: String
    let lines: [OrderLineDTO]
    let subtotalCents: Int
    let discountCents: Int
    let currency: String
    /// What this order is worth to them after commission — the number an owner
    /// actually reads.
    let earningsMinor: Int
    let note: String
    let addressLabel: String
    let courierName: String?
    /// NONE / SEARCHING / ASSIGNED / FAILED — a kitchen with food ready and
    /// nobody coming needs to know before the food does.
    let courierSearch: String
    let prepMinutes: Int
    let cancelReason: String
    let placedAt: String
    let acceptedAt: String?
    let readyAt: String?
    let statusChangedAt: String

    var itemCount: Int { lines.reduce(0) { $0 + $1.qty } }
    var needsAnswer: Bool { status == "CONFIRMED" }
    var noCourier: Bool { courierSearch == "FAILED" }
}

/// A prep estimate, or nil for the server's default. Not required, because an
/// accept that can fail validation is an accept somebody in a kitchen does not
/// make.
struct AcceptOrderBody: Encodable {
    let prepMinutes: Int?
}

struct RejectOrderBody: Encodable {
    let reason: String
}

// MARK: The courier's screen (Phase 4 M1)

/// A delivery from the other end: two addresses, what is in the bag and what it
/// pays — and deliberately nothing else about the customer. A courier needs to
/// find a door, not to know who lives behind it.
struct CourierJobDTO: Decodable, Identifiable {
    let id: UUID
    let status: String
    let merchantName: String
    let merchantLatitude: Double?
    let merchantLongitude: Double?
    let addressLabel: String
    let addressLine: String
    let addressNote: String
    let addressLatitude: Double?
    let addressLongitude: Double?
    let itemCount: Int
    let note: String
    /// The delivery fee plus whatever was tipped at checkout — and, since this
    /// milestone, money that actually reaches them.
    let payMinor: Int
    let currency: String
    let readyAt: String?
    let pickedUpAt: String?
    let statusChangedAt: String

    var isCollected: Bool { status == "DELIVERING" }
}

/// "Not carrying anything" is a 200 with a null job.
struct CourierJobResponseDTO: Decodable {
    let job: CourierJobDTO?
}

struct SavePromotionBody: Encodable {
    let code: String?
    let label: String
    let kind: String
    let valueBps: Int
    let amountCents: Int
    let minBasketCents: Int
    let maxDiscountCents: Int
    let perUserLimit: Int
}
