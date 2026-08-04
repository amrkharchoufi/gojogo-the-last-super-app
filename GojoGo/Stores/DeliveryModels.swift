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

/// One kitchen's slice of an order (Phase 4 M3).
///
/// `status` is the sub-order's own vocabulary — CONFIRMED / PREPARING /
/// COLLECTED / DELIVERED / CANCELLED — which sits beside the parent's six
/// words because "Dar Zellij is cooking, Sweet Corner turned theirs down" is
/// per-kitchen news the order status cannot carry.
struct SubOrderDTO: Decodable, Identifiable {
    let id: UUID
    let merchantId: UUID
    let merchantName: String
    let merchantImageUrl: String?
    let status: String
    /// Whether this slice alone can still be cancelled — true exactly while its
    /// kitchen hasn't answered. The server computes it so the app never
    /// re-derives the rule and gets it a version out of date.
    let cancellable: Bool
    let lines: [OrderLineDTO]
    let subtotalCents: Int
    let deliveryFeeCents: Int
    let discountCents: Int
    let promotionCode: String
    let prepMinutes: Int
    let readyAt: String?
    let collectedAt: String?
    let cancelReason: String

    var itemCount: Int { lines.reduce(0) { $0 + $1.qty } }
    var isCancelled: Bool { status == "CANCELLED" }
    var isCollected: Bool { status == "COLLECTED" || status == "DELIVERED" }

    /// What this kitchen's row says it is doing, in the customer's words.
    var progressLabel: String {
        switch status {
        case "CONFIRMED": return "Waiting for the restaurant"
        case "PREPARING": return "Cooking"
        case "COLLECTED": return "With your courier"
        case "DELIVERED": return "Delivered"
        default:          return cancelReason.isEmpty ? "Cancelled" : cancelReason
        }
    }
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
    /// When the kitchen says the food will be done. Null until they accept —
    /// and since Phase 4 M3 it is the *last* kitchen still cooking, which is
    /// what the countdown and the courier's pickup time are both drawn from.
    let readyAt: String?
    let lines: [OrderLineDTO]
    /// One per kitchen (Phase 4 M3). Optional-decoded like every field added
    /// after a release; the flat fields above stay populated either way, so a
    /// single-restaurant order renders identically whether or not this arrives.
    let subOrders: [SubOrderDTO]?
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
    /// PIN / PHOTO / CONFIRM — how this order gets handed over (Phase 4 M2).
    /// The customer's choice, changeable right up until it arrives, because
    /// "leave it at the door" is a decision people make when the courier is
    /// already close.
    let handoffMode: String?
    /// The six digits the courier has to be told. Server-side this is blank
    /// unless the order is live *and* in PIN mode, so the screen can render it
    /// whenever it is non-empty and never has to work out whether it should.
    let deliveryPin: String?
    /// A short-lived signed URL, minted per read and non-nil only once a PHOTO
    /// handoff has actually completed. The object key behind it never reaches
    /// this app — a key is a thing you can ask for again, and a URL expires.
    let proofPhotoUrl: String?
    /// The 1:1 thread with whoever is bringing it, opened by the server at
    /// assignment. Nil until then, and nil forever if opening it failed —
    /// which is deliberate on that side, so it must be survivable on this one.
    let conversationId: UUID?

    /// What the handoff control starts on. A backend that predates M2 sends
    /// nothing, and the honest reading of that is CONFIRM: it is what those
    /// orders actually do.
    var handoff: String { handoffMode ?? "CONFIRM" }

    /// The kitchens on this order, never empty: a backend that predates M3
    /// sends none, and one restaurant's order is exactly what it always was.
    var kitchens: [SubOrderDTO] { subOrders ?? [] }

    /// Whether this order is worth drawing as several kitchens. One is the
    /// overwhelming case and gets the screen it has always had.
    var spansKitchens: Bool { kitchens.count > 1 }
}

/// "Nothing in flight" is a 200 with a null order, not a 404.
struct ActiveOrderDTO: Decodable {
    let order: OrderDTO?
}

struct PlaceOrderLineBody: Encodable {
    let menuItemId: UUID
    let qty: Int
}

/// One kitchen's basket inside a checkout (Phase 4 M3).
struct BasketBody: Encodable {
    let merchantId: UUID
    let lines: [PlaceOrderLineBody]
    /// Per basket, because a promotion is one merchant's own campaign. Nil
    /// leaves the checkout-level code to be tried against this kitchen too.
    let promotionCode: String?
}

struct PlaceOrderBody: Encodable {
    /// The pre-M3 single-merchant fields. Left nil when `baskets` is used —
    /// the server takes either shape and refuses only when both are missing.
    let merchantId: UUID?
    let lines: [PlaceOrderLineBody]?
    /// One per kitchen. The app always sends this now; the fields above stay
    /// in the type because the wire still accepts them and a stale client in
    /// the field is still speaking that shape.
    let baskets: [BasketBody]?
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

/// PIN / PHOTO / CONFIRM. A word rather than an enum because the server owns
/// the list — a build that has never heard of a fourth mode should show the
/// order it can't render a mode for, not fail to decode it.
struct HandoffModeBody: Encodable {
    let mode: String
}

struct TipBody: Encodable {
    let tipCents: Int
}

// MARK: Checkout

struct QuoteBody: Encodable {
    let merchantId: UUID?
    let lines: [PlaceOrderLineBody]?
    let baskets: [BasketBody]?
    let promotionCode: String?
    let tipCents: Int
}

/// One kitchen's slice of a quote (Phase 4 M3) — what the checkout sheet
/// groups by, and where a shared code visibly landed.
struct MerchantQuoteDTO: Decodable, Identifiable {
    let merchantId: UUID
    let name: String
    let subtotalCents: Int
    let deliveryFeeCents: Int
    let discountCents: Int
    let promotionCode: String
    let promotionLabel: String

    var id: UUID { merchantId }
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
    /// The per-kitchen breakdown (Phase 4 M3), summing to the flat fields
    /// above. Optional-decoded: a backend that predates M3 sends none, and a
    /// one-restaurant checkout has nothing to group anyway.
    let merchants: [MerchantQuoteDTO]?
    let walletAvailableMinor: Int
    let walletCovers: Bool
    let shortfallMinor: Int

    var kitchens: [MerchantQuoteDTO] { merchants ?? [] }
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
    /// See `StripePayoutNeeds` — since Phase 4 M2 a courier has the same card
    /// and gets the same sentence, so the vocabulary lives in one place.
    var payoutsNeedSentence: String { StripePayoutNeeds.sentence(payoutsRequirement) }
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
    /// The six digits the counter reads out to the courier (Phase 4 M2).
    /// Minted when this restaurant accepted, and returned **only here** — a
    /// code the courier can read off their own screen proves nothing about
    /// where they are standing.
    let pickupCode: String?

    var itemCount: Int { lines.reduce(0) { $0 + $1.qty } }
    var needsAnswer: Bool { status == "CONFIRMED" }
    var noCourier: Bool { courierSearch == "FAILED" }

    /// Show the code once somebody is actually coming for the food, and stop
    /// showing it the moment they have it. A code on a delivered order is a
    /// number on a screen with nobody left to read it to.
    var readableCode: String? {
        guard let code = pickupCode, !code.isEmpty else { return nil }
        guard status == "PREPARING" || status == "COURIER_TO_RESTAURANT" else { return nil }
        return courierName == nil ? nil : code
    }
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
    /// The thread with the person waiting for this (Phase 4 M2). Nil until the
    /// server has opened it, and nil for good if opening it failed — a chat
    /// that didn't open must never have cost somebody the assignment.
    let conversationId: UUID?
    /// How this customer wants it handed over: `PIN`, `PHOTO` or `CONFIRM`.
    ///
    /// Neither *code* is here and neither ever will be — the pickup code is on
    /// the kitchen's DTO and the delivery PIN on the customer's, because a
    /// courier who could read either could collect food they are not standing
    /// in front of or confirm a delivery they never made. The mode is not one
    /// of those secrets. It is an instruction, in the same category as `note`:
    /// "leave it at the door" is something the person inside said, and an app
    /// that withholds it has a courier knocking on the door of somebody who
    /// asked them not to. It is optional here for the usual forward-compat
    /// reason — an older backend simply doesn't send it.
    let handoffMode: String?
    /// Every counter on this run, in collection order (Phase 4 M3). Each has
    /// its own code, shown on that kitchen's screen and never here — one code
    /// that opened every counter would prove presence at none of them.
    let stops: [CourierStopDTO]?

    var isCollected: Bool { status == "DELIVERING" }

    /// The stops, never empty: a backend that predates M3 sends none, and the
    /// single merchantName/lat/lng above are exactly that one stop.
    var counters: [CourierStopDTO] { stops ?? [] }

    /// What is still to be picked up. The screen leads with the first of these
    /// — the legacy `merchantName` points at the same place.
    var remainingStops: [CourierStopDTO] { counters.filter { !$0.collected } }

    var hasMultipleStops: Bool { counters.count > 1 }

    /// Whether this door asked for a photograph. Absent means no — an app that
    /// guessed "contactless" from a missing field would leave food on a step
    /// for somebody who was standing behind the door waiting for it.
    var wantsPhoto: Bool { handoffMode == "PHOTO" }
}

/// One counter on the courier's route (Phase 4 M3).
struct CourierStopDTO: Decodable, Identifiable {
    let subOrderId: UUID
    let merchantName: String
    let latitude: Double?
    let longitude: Double?
    let itemCount: Int
    let collected: Bool
    let readyAt: String?

    var id: UUID { subOrderId }
}

/// "Not carrying anything" is a 200 with a null job.
struct CourierJobResponseDTO: Decodable {
    let job: CourierJobDTO?
}

// MARK: Handoff integrity (Phase 4 M2)

/// The answer to "I have the food" / "I handed it over".
///
/// A 200 in both outcomes, and that is the design rather than a shortcut: a
/// courier at a door who typed a 7 for a 1 has not made a bad request, and a
/// screen that renders a refusal as an error renders it as *the app's* fault.
/// So a wrong code comes back here, with the server's own sentence and the
/// number of tries left, and the app puts it under the field.
struct HandoffResultDTO: Decodable {
    let accepted: Bool
    /// Always shown as written. Only the server knows whether the last attempt
    /// was the last one, and it says so in the message.
    let message: String
    /// Tries remaining before the photo fallback opens.
    ///
    /// **`-1` means "not counted", which is not the same as none left.** It is
    /// always `-1` on `picked-up` — the pickup code is never counted, because
    /// the merchant is standing right there and a courier who cannot get past
    /// the counter is a courier holding food nobody will take back — and it is
    /// `-1` on `delivered` for any order that is not in PIN mode, which has no
    /// budget to spend. Anything drawn from this must read it as "no count to
    /// show" rather than as zero, or a contactless drop renders as a courier
    /// out of chances.
    let attemptsLeft: Int
    /// Set once the delivery PIN has been failed to the limit: the photo path
    /// is now open on an order that asked for a code.
    let supportUnlocked: Bool
    /// The job as it now stands. Nil on the delivery that completed it — there
    /// is nothing left to carry.
    let job: CourierJobDTO?

    /// True only where a count is actually being kept.
    var isCounted: Bool { attemptsLeft >= 0 }
}

struct PickupCodeBody: Encodable {
    let pickupCode: String
}

/// Optional on purpose: a CONFIRM order and a PHOTO one both hand over without
/// one, and a body that insisted on an empty string would be the app inventing
/// a wrong answer rather than sending no answer.
struct DeliveryPinBody: Encodable {
    let pin: String?
}

/// A presigned PUT for the drop-off photo. The same four fields as
/// `DocumentUploadDTO` and deliberately a separate type: that one is `partner`'s
/// papers, this is `delivery`'s proof, and the day one of them grows a field is
/// not the day the other should.
///
/// The app never sends the key anywhere. The server minted it, so the server
/// already knows it — it is stamped onto the order inside the presign.
struct ProofUploadDTO: Decodable {
    let uploadUrl: String
    let objectKey: String
    let contentType: String
    let expiresSeconds: Int
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
