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
    let saveCount: Int
    let createdAt: String
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

struct CreateListingBody: Encodable {
    let title: String
    let priceCents: Int64?
    let currency: String
    let category: String
    let condition: String
    let locationLabel: String
    let description: String
    let imageUrls: [String]
}
