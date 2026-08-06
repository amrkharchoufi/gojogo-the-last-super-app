import Foundation

// MARK: - Merchant catalog DTOs (Phase 5 · Milestones 1 & 2)
//
// The *other* half of `economy`. `EconomyModels` next door is the C2C shelf —
// one person selling one thing, a price and a photo. This is the provisioned
// seller's catalog: products with variants, counted stock, a server-priced
// checkout and an order that settles when the buyer says it arrived.
//
// They stay two sets of shapes on purpose. A listing has no stock, no variant
// and no order behind it, and the day somebody folds them together is the day
// a listing needs a `variants` field nobody can fill in.
//
// Timestamps are `String` by the same convention the rest of the app uses and
// parsed with `BackendDate` at the point of use. Money is integer cents.

// MARK: Seller

/// The shop as its owner configures it. `currency` comes from the platform's
/// own config rather than from the seller — one currency, one ledger.
struct ShopSellerDTO: Decodable {
    let id: UUID
    let displayName: String
    let logoUrl: String?
    let shippingFlatCents: Int
    let freeShippingOverCents: Int
    /// Basis points: 875 = 8.75% tax. Applied server-side at checkout.
    let taxBps: Int
    let suspended: Bool
    let currency: String
}

struct ShopSellerBody: Encodable {
    let displayName: String
    let logoUrl: String?
    let shippingFlatCents: Int
    let freeShippingOverCents: Int
    let taxBps: Int
}

// MARK: Catalog

/// One buyable configuration of a product — a size, a colour, a bundle. Every
/// product has at least one, so the buyer's "add to basket" always names a
/// variant and the price is never on the product itself.
struct ShopVariantDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let sku: String?
    let label: String
    let priceCents: Int64
    let stock: Int
    let active: Bool

    var inStock: Bool { active && stock > 0 }
}

/// What the seller posts back. `id` is present when editing an existing
/// variant and nil for a new one — a variant that disappears from this list is
/// *retired* server-side, never deleted, because order lines point at it
/// forever.
struct ShopVariantBody: Encodable {
    let id: UUID?
    let sku: String?
    let label: String
    let priceCents: Int64
    let stock: Int
    let active: Bool
}

struct ShopProductDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let sellerId: UUID
    let sellerName: String
    let sellerLogoUrl: String?
    let name: String
    let description: String?
    let category: String?
    let brand: String?
    /// PHYSICAL / DIGITAL. Optional-decoded so a response written before the
    /// special catalogs still reads as something shippable.
    let kind: String?
    let specs: String?
    let imageUrls: [String]
    let variants: [ShopVariantDTO]
    let active: Bool
    let averageRating: Double?
    let ratingCount: Int
    let createdAt: String
    let updatedAt: String?

    var isDigital: Bool { kind?.uppercased() == "DIGITAL" }

    /// The cheapest live variant — what a grid card shows, since the card has
    /// no room to ask which size you meant.
    var fromPriceCents: Int64? {
        variants.filter(\.inStock).map(\.priceCents).min()
            ?? variants.map(\.priceCents).min()
    }

    var anyInStock: Bool { variants.contains(where: \.inStock) }

    var priceLabel: String {
        EconomyStore.formatPrice(cents: fromPriceCents, currency: "USD")
    }

    var imageURL: String? { imageUrls.first }
}

struct ShopProductPageDTO: Decodable {
    let items: [ShopProductDTO]
    let nextBefore: String?
}

struct ShopProductBody: Encodable {
    let name: String
    let description: String
    let category: String
    let brand: String
    let specs: String
    let imageUrls: [String]
    let variants: [ShopVariantBody]
    /// PHYSICAL or DIGITAL. Fixed at creation: a product that has sold as one
    /// cannot become the other without lying about what past orders delivered.
    let kind: String
}

// MARK: Orders

struct ShopOrderLineDTO: Decodable, Identifiable, Equatable {
    let productId: UUID
    let variantId: UUID
    let productName: String
    let variantLabel: String
    let unitPriceCents: Int64
    let quantity: Int
    let lineTotalCents: Int64

    /// Lines have no id of their own on the wire — the variant is unique within
    /// an order, which is what `ForEach` actually needs.
    var id: UUID { variantId }
}

/// Four words, not delivery's six: what happens between posted and arrived is
/// a carrier's business this system cannot observe.
enum ShopOrderStatus: String, CaseIterable, Identifiable {
    case placed = "PLACED"
    case shipped = "SHIPPED"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"

    var id: String { rawValue }

    /// An unknown word reads as `placed` rather than crashing a list: a newer
    /// backend must never be able to blank a buyer's order history.
    init(wire: String?) {
        self = wire.flatMap { ShopOrderStatus(rawValue: $0.uppercased()) } ?? .placed
    }

    var label: String {
        switch self {
        case .placed: return "Placed"
        case .shipped: return "On its way"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var icon: String {
        switch self {
        case .placed: return "shippingbox"
        case .shipped: return "truck.box"
        case .completed: return "checkmark.seal.fill"
        case .cancelled: return "xmark.circle"
        }
    }
}

struct ShopOrderDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let sellerId: UUID
    let sellerName: String
    let status: String
    let subtotalCents: Int
    let discountCents: Int
    let shippingCents: Int
    let taxCents: Int
    let totalCents: Int
    let currency: String
    let promotionLabel: String?
    let shipTo: String?
    let trackingNote: String?
    let lines: [ShopOrderLineDTO]
    let placedAt: String
    let shippedAt: String?
    let completedAt: String?
    let cancelledAt: String?

    var state: ShopOrderStatus { ShopOrderStatus(wire: status) }

    var totalLabel: String {
        EconomyStore.formatPrice(cents: Int64(totalCents), currency: currency)
    }

    /// The money moves on this tap, so the button only exists while it can.
    var canConfirmReceived: Bool { state == .shipped || state == .placed }

    /// A digital order settles at checkout — there is nothing to ship, nothing
    /// to receive, and no window in which either party can pull out.
    var isSettled: Bool { state == .completed || state == .cancelled }
}

struct ShopCheckoutLine: Encodable {
    let variantId: UUID
    let quantity: Int
}

/// A basket line, on the device only. The server never sees a basket — it sees
/// a checkout, priced from its own catalog — so everything here is display
/// state, and the price in it is what the buyer was *shown*, to be checked
/// against what the server charges rather than trusted.
struct ShopBasketLine: Identifiable, Equatable {
    let productId: UUID
    let variantId: UUID
    let sellerId: UUID
    let sellerName: String
    let productName: String
    let variantLabel: String
    let unitPriceCents: Int64
    let imageURL: String?
    /// Digital lines can't be mixed with physical ones in a single checkout —
    /// one order cannot both complete at capture and weeks later.
    let isDigital: Bool
    var quantity: Int
    /// What the seller said was left when this went in the basket. Checkout is
    /// still the authority; this only stops the stepper going past it.
    var stock: Int

    var id: UUID { variantId }

    var lineTotalCents: Int64 { unitPriceCents * Int64(quantity) }
}

struct ShopCheckoutBody: Encodable {
    let lines: [ShopCheckoutLine]
    let shipTo: String?
    let promotionCode: String?
}

struct ShopShipBody: Encodable {
    let trackingNote: String
}

// MARK: Reviews

struct ShopReviewDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let productId: UUID
    let authorId: UUID
    let authorName: String?
    let authorAvatarUrl: String?
    let rating: Int
    let body: String?
    let photoUrls: [String]?
    /// The seller's single reply, as a column on the review — one answer per
    /// review, which is what stops a product page becoming a comment thread.
    let replyBody: String?
    let repliedAt: String?
    let createdAt: String
}

struct ShopReviewBody: Encodable {
    /// Verified purchase: the review names the completed order it rides on.
    let orderId: UUID
    let rating: Int
    let body: String
    let photoUrls: [String]
}

struct ShopReplyBody: Encodable {
    let body: String
}

// MARK: Promotions

struct ShopPromotionDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let code: String?
    let label: String?
    /// PERCENT / FIXED / FREE_SHIPPING.
    let kind: String
    let valueBps: Int
    let amountCents: Int
    let minBasketCents: Int
    let maxDiscountCents: Int
    let perUserLimit: Int
    let active: Bool
    let startsAt: String?
    let endsAt: String?

    var valueLabel: String {
        switch kind.uppercased() {
        case "PERCENT": return "\(valueBps / 100)% off"
        case "FIXED": return "\(EconomyStore.formatPrice(cents: Int64(amountCents), currency: "USD")) off"
        default: return "Free shipping"
        }
    }
}

struct ShopPromotionBody: Encodable {
    let code: String
    let label: String
    let kind: String
    let valueBps: Int
    let amountCents: Int
    let minBasketCents: Int
    let maxDiscountCents: Int
    let perUserLimit: Int
    let startsAt: String?
    let endsAt: String?
}

// MARK: Digital (Phase 5 M2)

/// What a digital purchase granted. Minted at capture, in the same transaction
/// as the payment — there is no window in which the money has moved and the
/// buyer owns nothing.
struct ShopEntitlementDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let productId: UUID
    let productName: String
    /// DOWNLOAD or LICENSE_KEY.
    let kind: String
    let licenseKey: String?
    let fileName: String?
    let expiresAt: String?
    let createdAt: String

    var isDownload: Bool { kind.uppercased() == "DOWNLOAD" }
}

struct ShopDownloadDTO: Decodable {
    let url: String
}

/// A presigned PUT for a private object. The client never learns a readable
/// URL — it keeps the object key, which grants nothing on its own.
struct ShopUploadDTO: Decodable {
    let uploadUrl: String
    let objectKey: String
    let contentType: String?
    let expiresSeconds: Int?
}

struct ShopDigitalAssetBody: Encodable {
    let objectKey: String
    let fileName: String
    let contentType: String
    /// DOWNLOAD / LICENSE_KEY.
    let entitlementKind: String
}

// MARK: Ownership transfer (Phase 5 M2)

/// SPECS §6's transfer machine. Escrow comes *before* the document check, so a
/// reviewer's time is only ever spent on a deal that is real.
enum TransferState: String, CaseIterable, Identifiable {
    case inquiry = "INQUIRY"
    case offerAccepted = "OFFER_ACCEPTED"
    case paymentHeld = "PAYMENT_HELD"
    case docsConfirmed = "DOCS_CONFIRMED"
    case transferred = "TRANSFERRED"
    case released = "RELEASED"
    case cancelled = "CANCELLED"

    var id: String { rawValue }

    init(wire: String?) {
        self = wire.flatMap { TransferState(rawValue: $0.uppercased()) } ?? .inquiry
    }

    var label: String {
        switch self {
        case .inquiry: return "Enquiry"
        case .offerAccepted: return "Price agreed"
        case .paymentHeld: return "In escrow"
        case .docsConfirmed: return "Papers checked"
        case .transferred: return "Handed over"
        case .released: return "Complete"
        case .cancelled: return "Cancelled"
        }
    }

    /// What the *buyer* is waiting on, in the buyer's own words.
    var buyerHint: String {
        switch self {
        case .inquiry: return "Waiting for the seller to name a price."
        case .offerAccepted: return "Pay to put the money in escrow."
        case .paymentHeld: return "Held. A reviewer is checking the paperwork."
        case .docsConfirmed: return "Papers checked — confirm once it's yours."
        case .transferred: return "Confirmed. The seller is being paid."
        case .released: return "Done. The money has gone to the seller."
        case .cancelled: return "Cancelled. Anything held was returned."
        }
    }
}

struct TransferDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let listingId: UUID
    let listingTitle: String?
    let vinSerial: String?
    let sellerId: UUID
    let buyerId: UUID
    let state: String
    let priceCents: Int64?
    let currency: String?
    /// Over the platform's wallet cap: settled by hand rather than half-held.
    let flaggedManual: Bool
    let createdAt: String
    let acceptedAt: String?
    let paidAt: String?
    let docsConfirmedAt: String?
    let transferredAt: String?
    let releasedAt: String?
    let cancelledAt: String?
    let cancelNote: String?

    var step: TransferState { TransferState(wire: state) }

    var priceLabel: String {
        EconomyStore.formatPrice(cents: priceCents, currency: currency ?? "USD")
    }
}

struct TransferAcceptBody: Encodable {
    let priceCents: Int64
}

struct TransferCancelBody: Encodable {
    let note: String
}

struct TransferDocumentBody: Encodable {
    let objectKey: String
    let label: String
}

struct TransferDocumentDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let label: String
    /// Short-lived and minted per ask — never cached, never stored.
    let readUrl: String?
    let uploadedAt: String
}

// MARK: Wallet

/// The five pockets. A seller only ever sees `available` move, but the shape
/// is the platform's own and decoding it whole means a new bucket doesn't
/// break this screen.
struct WalletBalancesDTO: Decodable, Equatable {
    let currency: String
    let available: Int64
    let escrow: Int64
    let staking: Int64
    let tokens: Int64
    let rewards: Int64
}

struct WalletEntryDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let amountMinor: Int64
    let currency: String
    let kind: String
    let refKind: String?
    let refId: UUID?
    let memo: String?
    let createdAt: String

    var isCredit: Bool { amountMinor >= 0 }

    var amountLabel: String {
        let sign = isCredit ? "+" : "−"
        return sign + EconomyStore.formatPrice(cents: abs(amountMinor), currency: currency)
    }
}

struct PayeeWalletDTO: Decodable, Equatable {
    let balances: WalletBalancesDTO
    let entries: [WalletEntryDTO]
}
