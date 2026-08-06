import Foundation

// MARK: - Search (Phase 5 · Milestone 4)
//
// One query across four kinds, ranked server-side by relevance × log-damped
// popularity. The store is Postgres full-text rather than the OpenSearch SPECS
// named, which the client cannot tell and must not care about: everything here
// talks to `GET /v1/search`, and the day a cluster appears behind it, no line
// of this file changes.

/// What a hit points at. The four the backend indexes today — merchants,
/// videos and business profiles are deferred until their modules publish an
/// upsert signal, so a fifth constant here would be a filter that finds
/// nothing.
enum SearchKind: String, CaseIterable, Identifiable {
    case post = "POST"
    case listing = "LISTING"
    case product = "PRODUCT"
    case service = "SERVICE"

    var id: String { rawValue }

    init?(wire: String?) {
        guard let raw = wire?.uppercased(), let kind = SearchKind(rawValue: raw) else { return nil }
        self = kind
    }

    var label: String {
        switch self {
        case .post: return "Posts"
        case .listing: return "Marketplace"
        case .product: return "Shops"
        case .service: return "Services"
        }
    }

    var icon: String {
        switch self {
        case .post: return "text.bubble"
        case .listing: return "tag"
        case .product: return "bag"
        case .service: return "wrench.and.screwdriver"
        }
    }
}

/// One indexed thing. `refId` is the id in the *owning* module — a post id, a
/// listing id — which is what makes a result tappable without search knowing
/// what any of them are.
struct SearchHitDTO: Decodable, Identifiable, Equatable {
    let refId: UUID
    let kind: String
    let title: String
    let snippet: String?
    let category: String?
    let popularity: Int
    let updatedAt: String?

    /// Two kinds can in principle carry the same ref id; the pair is the row.
    var id: String { "\(kind):\(refId.uuidString)" }

    var searchKind: SearchKind? { SearchKind(wire: kind) }
}

@MainActor
final class SearchStore {

    static let shared = SearchStore()

    func search(_ query: String, kind: SearchKind? = nil, limit: Int = 25) async throws -> [SearchHitDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return [] }
        var path = "/v1/search?q=\(encoded)&limit=\(limit)"
        if let kind { path += "&kind=\(kind.rawValue)" }
        return try await APIClient.shared.get(path)
    }

    /// The trending rail. An aggregate on a 15-minute server-side cache, so
    /// asking more often than the screen is opened buys nothing.
    func trending(kind: SearchKind? = nil, limit: Int = 20) async throws -> [SearchHitDTO] {
        var path = "/v1/search/trending?limit=\(limit)"
        if let kind { path += "&kind=\(kind.rawValue)" }
        return try await APIClient.shared.get(path)
    }
}
