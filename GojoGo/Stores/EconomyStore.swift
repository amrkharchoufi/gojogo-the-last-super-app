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

    func reset() {
        remoteListingIds = []
    }

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
        page.listings.forEach { remoteListingIds.insert($0.id) }
        return (page.listings.map(map), page.nextBefore)
    }

    func saved(limit: Int = 50) async throws -> [Product] {
        let dtos: [ListingDTO] = try await APIClient.shared.get("/v1/economy/saved?limit=\(limit)")
        dtos.forEach { remoteListingIds.insert($0.id) }
        return dtos.map(map)
    }

    func mine(limit: Int = 50) async throws -> [Product] {
        let dtos: [ListingDTO] = try await APIClient.shared.get("/v1/economy/listings/mine?limit=\(limit)")
        dtos.forEach { remoteListingIds.insert($0.id) }
        return dtos.map(map)
    }

    // MARK: Mutations

    func create(_ body: CreateListingBody) async throws -> Product {
        let dto: ListingDTO = try await APIClient.shared.post("/v1/economy/listings", body: body)
        remoteListingIds.insert(dto.id)
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

    // MARK: Mapping

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
