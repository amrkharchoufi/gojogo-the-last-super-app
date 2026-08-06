import Foundation

// MARK: - Economy module DTOs (Phase 2b · Milestone 1)
//
// Mirror the backend `economy` records. Prices are integer cents + currency;
// the store formats a display string for the SwiftUI `Product` model.

struct SellerSummaryDTO: Decodable {
    let id: UUID
    let name: String?
    let handle: String?
    let avatarUrl: String?
}

struct ListingDTO: Decodable {
    let id: UUID
    let seller: SellerSummaryDTO
    let title: String
    let priceCents: Int64?
    let currency: String
    let category: String
    let condition: String
    let locationLabel: String
    let description: String
    let imageUrls: [String]
    let saved: Bool
    let isOwn: Bool
    /// ACTIVE / PAUSED / SOLD. Only ACTIVE listings come back from browse.
    /// Optional-decoded, like `viewCount`: a backend that predates listing
    /// management doesn't send either, and the marketplace still has to work.
    let status: String?
    let saveCount: Int
    let viewCount: Int?
    /// SALE or OWNERSHIP_TRANSFER (Phase 5 M2). Optional-decoded like the two
    /// above: a listing that predates the transfer catalog is an ordinary sale,
    /// and reading it as anything else would put an escrow button on a bicycle.
    let kind: String?
    /// A chassis, plate or serial — the thing the paperwork is *about*. Only
    /// ever present on a transfer listing.
    let vinSerial: String?
    let createdAt: String
    /// Null until the seller first edits the listing.
    let updatedAt: String?
}

struct ListingPageDTO: Decodable {
    let listings: [ListingDTO]
    let nextBefore: String?
}

/// Where a listing conversation lives, plus a ready-made opener. The backend
/// creates (or reuses) the thread but posts nothing — the client prefills the
/// composer so the buyer still chooses to send.
struct ListingChatDTO: Decodable {
    let conversationId: UUID
    let sellerId: UUID
    let suggestedMessage: String
}

/// Create and edit post the same shape: the edit form sends the whole listing
/// back, photos included, so an omitted field means "clear it".
struct ListingBody: Encodable {
    let title: String
    let priceCents: Int64?
    let currency: String
    let category: String
    let condition: String
    let locationLabel: String
    let description: String
    let imageUrls: [String]
    /// SALE or OWNERSHIP_TRANSFER (Phase 5 M2). Sent on create and on edit
    /// because this is a whole-object upsert — omitting it would quietly turn a
    /// transfer listing back into an ordinary sale on the seller's next edit.
    let kind: String
    /// The chassis, plate or serial the paperwork is about. Only meaningful on
    /// a transfer, and the server ignores it on anything else.
    let vinSerial: String
}

struct ListingStatusBody: Encodable {
    let status: String
}

// MARK: - Seller view (Phase 2b · Milestone 5)

/// The seller's own totals, across every listing rather than the page in hand.
struct SellerStatsDTO: Decodable {
    let total: Int
    let active: Int
    let paused: Int
    let sold: Int
    let saves: Int
    let views: Int
}

/// Where a listing is in its life. Only `.active` listings appear in browse;
/// the other two stay on the seller's shelf, so a sale doesn't look like a
/// deletion to the seller or to anyone who saved the item.
enum ListingStatus: String, CaseIterable, Identifiable {
    case active = "ACTIVE"
    case paused = "PAUSED"
    case sold = "SOLD"

    var id: String { rawValue }

    /// A missing value (older backend) or an unknown one (newer backend) reads
    /// as live — a listing is better shown than silently vanished.
    init(wire: String?) {
        self = wire.flatMap { ListingStatus(rawValue: $0.uppercased()) } ?? .active
    }

    var label: String {
        switch self {
        case .active: return "Live"
        case .paused: return "Paused"
        case .sold: return "Sold"
        }
    }

    var icon: String {
        switch self {
        case .active: return "dot.radiowaves.left.and.right"
        case .paused: return "pause.circle"
        case .sold: return "checkmark.seal.fill"
        }
    }
}

/// A listing as its *seller* sees it: the raw fields the edit form posts back,
/// plus the numbers "Your listings" shows. Deliberately not `Product` — that's
/// the buyer's view, and it carries a formatted price and a single photo.
struct SellerListing: Identifiable, Equatable {
    let id: UUID
    var title: String
    var priceCents: Int64?
    var currency: String
    var category: String
    var condition: String
    var locationLabel: String
    var description: String
    var imageURLs: [String]
    /// Carried on the seller's own copy because the edit form posts the whole
    /// listing back: a kind that isn't in the body is a transfer listing that
    /// silently becomes an ordinary sale the first time its seller fixes a typo.
    var kind: String
    var vinSerial: String
    var status: ListingStatus
    var saveCount: Int
    var viewCount: Int
    let createdAt: String
    var updatedAt: String?

    var priceLabel: String {
        EconomyStore.formatPrice(cents: priceCents, currency: currency)
    }

    var imageURL: String? { imageURLs.first }

    /// "3d ago", or "just now" inside the first minute.
    var ageLabel: String { Self.ago(createdAt) }

    /// "Listed 3d ago · edited 1h ago" — the second half only once it applies.
    var timelineLabel: String {
        let listed = "Listed \(ageLabel)"
        guard let updatedAt else { return listed }
        return "\(listed) · edited \(Self.ago(updatedAt))"
    }

    private static func ago(_ raw: String) -> String {
        let relative = BackendDate.relative(raw)
        return relative == "now" ? "just now" : "\(relative) ago"
    }
}
