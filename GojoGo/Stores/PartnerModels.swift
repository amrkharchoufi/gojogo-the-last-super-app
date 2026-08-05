import Foundation

// MARK: - Wire types (partner module)
//
// Restaurants are created in **Gojo Admin**, not here (2026-07-27). The app
// reads the partner account only to answer two questions about someone who
// already manages a restaurant: is it live, and if it's suspended, why. The
// applicant-facing endpoints (`POST /v1/partner/applications` and the private
// KYC upload) still exist on the server and are simply not called from iOS.

/// The partner account behind a restaurant. Trimmed to what the app renders —
/// the business identity, contact details and KYC documents are the admin
/// tool's business, and the server sends them whether we decode them or not.
struct PartnerAccountDTO: Decodable, Equatable {
    let id: UUID
    let kind: String
    let status: String
    let businessName: String
    let category: String?
    /// Why a reviewer suspended them. Shown verbatim on the dashboard.
    let reviewNote: String?
    /// The `delivery.merchant` this account was provisioned into.
    let refId: UUID?
}

struct MyPartnerResponseDTO: Decodable {
    let account: PartnerAccountDTO?
}

// MARK: - Wire types (the owner's restaurant, delivery module)

struct MyMenuItemDTO: Decodable, Equatable {
    let id: UUID
    let name: String
    let detail: String?
    let priceCents: Int
    let imageUrl: String?
    let popular: Bool
    let available: Bool
}

struct MyMenuSectionDTO: Decodable, Equatable {
    let id: UUID
    let name: String
    let items: [MyMenuItemDTO]
}

struct MyMerchantDTO: Decodable, Equatable {
    let id: UUID
    let name: String
    let cuisine: String
    let imageUrl: String?
    let promo: String?
    let etaMinutes: Int
    let deliveryFeeCents: Int
    let rating: Double
    let reviewCount: Int
    let latitude: Double
    let longitude: Double
    let categories: [String]
    let tags: [String]
    let open: Bool
    let suspended: Bool
    /// Collection (Phase 4 M4). Optional-decoded like every field added after a
    /// release; false and nil are what a backend without collection means.
    /// `pickupPrepMinutes` nil is "the same as delivery" — the editor shows a
    /// placeholder rather than inventing a number nobody chose.
    let pickupEnabled: Bool?
    let pickupPrepMinutes: Int?
    let pickupAddress: String?
    /// Opening hours (Phase 4 M6). Blank is always open, which is what every
    /// restaurant was before this. `openNow` is the server's own reading of the
    /// schedule in the restaurant's timezone.
    let openingHours: String?
    let timezone: String?
    let openNow: Bool?
    let menu: [MyMenuSectionDTO]

    var offersPickup: Bool { pickupEnabled == true }
    var isOpenNow: Bool { openNow ?? true }
}

struct UpdateMerchantBody: Encodable {
    var name: String
    var cuisine: String
    var imageUrl: String?
    var promo: String?
    var etaMinutes: Int
    var deliveryFeeCents: Int
    var latitude: Double?
    var longitude: Double?
    var categories: [String]
    var tags: [String]
    /// Nil means "leave it as it is" on the server, which is what lets this
    /// build and an older one save the same restaurant without one of them
    /// silently switching collection off.
    var pickupEnabled: Bool?
    var pickupPrepMinutes: Int?
    var pickupAddress: String?
    /// The weekly schedule and the restaurant's timezone (Phase 4 M6). Nil is
    /// "leave it as it is", for the same reason as the pickup fields above.
    var openingHours: String?
    var timezone: String?
}

struct MenuSectionBody: Encodable {
    let name: String
}

/// `sectionId` is only read on update, where it moves a dish between sections;
/// on create the section comes from the path.
struct MenuItemBody: Encodable {
    var name: String
    var detail: String
    var priceCents: Int
    var imageUrl: String?
    var popular: Bool
    var available: Bool
    var sectionId: UUID?
}

struct SetOpenBody: Encodable {
    let open: Bool
}

// MARK: - UI models

/// Where a partner account stands. Mirrors the server's enum; anything
/// unrecognised reads as `draft`, so a newer backend can add a state without
/// bricking an older build (the same forward-compat convention as
/// `ListingStatus`).
///
/// Only `approved` and `suspended` are reachable from the app — the rest belong
/// to a review the operator runs in Gojo Admin.
enum MerchantApplicationStatus: String, Equatable {
    case draft = "DRAFT"
    case submitted = "SUBMITTED"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case suspended = "SUSPENDED"

    init(wire: String) { self = MerchantApplicationStatus(rawValue: wire) ?? .draft }

    var label: String {
        switch self {
        case .draft:     return "Draft"
        case .submitted: return "In review"
        case .approved:  return "Approved"
        case .rejected:  return "Needs changes"
        case .suspended: return "Suspended"
        }
    }

    /// What the GojoDelivery header chip reads. The chip only appears for a
    /// provisioned restaurant, so the other cases are a neutral fallback.
    var chipLabel: String { self == .suspended ? "Suspended" : "Your restaurant" }

    var icon: String { self == .suspended ? "pause.circle" : "storefront" }
}

/// The partner account as the app renders it — what the dashboard needs, and
/// nothing else.
struct MerchantAccount: Identifiable, Equatable {
    let id: UUID
    var status: MerchantApplicationStatus
    var businessName: String
    var category: String
    /// The reviewer's own words when a restaurant was suspended.
    var reviewNote: String?
    /// The restaurant this account manages; nil until Gojo Admin provisions one.
    var merchantID: UUID?
}

/// The restaurant, as its owner manages it.
struct MerchantStorefront: Equatable {
    let id: UUID
    var name: String
    var cuisine: String
    var imageURL: String?
    var promo: String?
    var etaMinutes: Int
    var deliveryFeeCents: Int
    var rating: Double
    var reviewCount: Int
    var latitude: Double
    var longitude: Double
    var categories: [String]
    var tags: [String]
    var isOpen: Bool
    var isSuspended: Bool
    /// Collection (Phase 4 M4). `pickupPrepMinutes` nil means "the same as
    /// delivery" — a kitchen that has not said so is not one to invent a faster
    /// number for.
    var offersPickup: Bool
    var pickupPrepMinutes: Int?
    var pickupAddress: String
    /// The weekly schedule in its stored form, and whether it says they are
    /// open right now (Phase 4 M6).
    var openingHours: String
    var openNow: Bool
    var menu: [MerchantMenuSection]

    var dishCount: Int { menu.reduce(0) { $0 + $1.items.count } }
    var availableCount: Int { menu.reduce(0) { $0 + $1.items.filter(\.isAvailable).count } }

    var feeLabel: String {
        deliveryFeeCents == 0
            ? "Free delivery"
            : String(format: "$%.2f delivery", Double(deliveryFeeCents) / 100)
    }
}

struct MerchantMenuSection: Identifiable, Equatable {
    let id: UUID
    var name: String
    var items: [MerchantMenuItem]
}

struct MerchantMenuItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var detail: String
    var priceCents: Int
    var imageURL: String?
    var isPopular: Bool
    var isAvailable: Bool

    var priceLabel: String { String(format: "$%.2f", Double(priceCents) / 100) }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
