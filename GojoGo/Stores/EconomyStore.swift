import SwiftUI

/// Economy-module API surface (marketplace listings, sell flow, saves) plus
/// DTO→`Product` mapping. Server listing UUIDs are reused as the `Product` ids
/// so save/delete can address the backend directly.
@MainActor
final class EconomyStore {

    static let shared = EconomyStore()

    /// Server-backed listing ids — AppState uses these to decide whether a save
    /// toggle should hit the API or stay local (SampleData catalog).
    private(set) var remoteListingIds: Set<UUID> = []
    /// Listings the signed-in user is selling — you can't message yourself.
    private(set) var ownListingIds: Set<UUID> = []

    func reset() {
        remoteListingIds = []
        ownListingIds = []
    }

    func isRemote(_ listingId: UUID) -> Bool { remoteListingIds.contains(listingId) }

    func isOwn(_ listingId: UUID) -> Bool { ownListingIds.contains(listingId) }

    // MARK: Browse / detail

    func browse(category: String? = nil, before: String? = nil, limit: Int = 24) async throws
        -> (products: [Product], nextBefore: String?) {
        var path = "/v1/economy/listings?limit=\(limit)"
        if let category, category != "All",
           let enc = category.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&category=\(enc)"
        }
        if let before,
           let enc = before.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&before=\(enc)"
        }
        let page: ListingPageDTO = try await APIClient.shared.get(path)
        track(page.listings)
        return (page.listings.map(map), page.nextBefore)
    }

    func saved(limit: Int = 50) async throws -> [Product] {
        let dtos: [ListingDTO] = try await APIClient.shared.get("/v1/economy/saved?limit=\(limit)")
        track(dtos)
        return dtos.map(map)
    }

    func mine(limit: Int = 50) async throws -> [Product] {
        let dtos: [ListingDTO] = try await APIClient.shared.get("/v1/economy/listings/mine?limit=\(limit)")
        track(dtos)
        return dtos.map(map)
    }

    // MARK: Mutations

    func create(_ body: CreateListingBody) async throws -> Product {
        let dto: ListingDTO = try await APIClient.shared.post("/v1/economy/listings", body: body)
        track([dto])
        return map(dto)
    }

    func save(_ listingId: UUID) async throws {
        try await APIClient.shared.post("/v1/economy/listings/\(listingId)/save")
    }

    func unsave(_ listingId: UUID) async throws {
        try await APIClient.shared.delete("/v1/economy/listings/\(listingId)/save")
    }

    func delete(_ listingId: UUID) async throws {
        try await APIClient.shared.delete("/v1/economy/listings/\(listingId)")
    }

    // MARK: Seller chat

    /// Opens (or reuses) the buyer↔seller thread for a listing. The backend
    /// sends nothing — the caller prefills `suggestedMessage` in the composer.
    func startChat(_ listingId: UUID) async throws -> ListingChatDTO {
        try await APIClient.shared.post("/v1/economy/listings/\(listingId)/chat")
    }

    // MARK: Mapping

    /// Remembers which listings came from the server and which are the caller's
    /// own, so the UI can pick the live path over the SampleData one.
    private func track(_ dtos: [ListingDTO]) {
        for dto in dtos {
            remoteListingIds.insert(dto.id)
            if dto.isOwn { ownListingIds.insert(dto.id) } else { ownListingIds.remove(dto.id) }
        }
    }

    func map(_ dto: ListingDTO) -> Product {
        let sellerName = dto.seller.name ?? dto.seller.handle ?? "seller"
        return Product(
            id: dto.id,
            name: dto.title,
            price: Self.formatPrice(cents: dto.priceCents, currency: dto.currency),
            meta: "\(sellerName) · \(BackendDate.relative(dto.createdAt))",
            gradient: SocialStore.gradient(for: dto.seller.handle ?? dto.title),
            imageURL: dto.imageUrls.first,
            saved: dto.saved,
            category: dto.category,
            seller: dto.seller.handle ?? sellerName,
            condition: dto.condition,
            distance: dto.locationLabel,
            description: dto.description)
    }

    static func formatPrice(cents: Int64?, currency: String) -> String {
        guard let cents else { return "$—" }
        let symbol = currency == "USD" ? "$" : "\(currency) "
        let whole = cents / 100
        let frac = abs(cents % 100)
        let grouped = groupThousands(whole)
        return frac == 0 ? "\(symbol)\(grouped)" : "\(symbol)\(grouped).\(String(format: "%02d", frac))"
    }

    private static func groupThousands(_ value: Int64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Parses a free-text price field ("$1,200", "45", "") into integer cents.
    static func parseCents(_ text: String) -> Int64? {
        let digits = text.filter { $0.isNumber || $0 == "." }
        guard !digits.isEmpty, let dollars = Double(digits) else { return nil }
        return Int64((dollars * 100).rounded())
    }
}
