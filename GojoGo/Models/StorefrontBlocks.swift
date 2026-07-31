import Foundation

// MARK: - Storefront blocks (Phase 2e · Milestone 4)
//
// A business arranges its own page out of a closed set of blocks (SPECS §9).
// The document is authored elsewhere — GoJoAdmin's Studio, later — and this app
// only ever *renders* it: there is no editor here, on purpose.
//
// Two rules make that safe to ship before the console exists:
//
//   1. A block type this build doesn't know is **skipped silently**. That is the
//      forward-compat contract: the server may start accepting a new type the
//      day it ships, and an app three releases old shows the rest of the page
//      instead of an error or a blank screen.
//   2. Every reference is resolved against data the screen already has. A
//      featured dish that is sold out simply isn't in the menu the detail fetch
//      returned, so the rail quietly gets shorter — which is the correct
//      behaviour, and the alternative is a tappable card that 400s at checkout.

// MARK: Wire

/// Something a block points at: `{"kind": "ITEM", "id": "…"}`.
struct StorefrontRefDTO: Decodable, Hashable {
    /// ITEM / SECTION / PROMOTION / POST / VIDEO.
    let kind: String
    let id: UUID
}

/// One block, flat exactly as the server stores it. Every property beyond
/// `id`/`type` is optional because most of them belong to one block type — the
/// server refuses a block carrying a property its type has no meaning for, so
/// what arrives here is already coherent.
struct StorefrontBlockDTO: Decodable {
    let id: String
    let type: String
    let title: String?
    let headline: String?
    let subheadline: String?
    let body: String?
    let mediaUrl: String?
    let ctaLabel: String?
    let ctaTarget: StorefrontRefDTO?
    let itemIds: [UUID]?
    let promotionId: UUID?
    let media: [StorefrontRefDTO]?
}

/// `version` is the author's counter, not a schema number: 0 means nobody has
/// ever arranged this page, which is every merchant until Studio exists.
struct StorefrontDTO: Decodable {
    let version: Int
    let blocks: [StorefrontBlockDTO]
}

// MARK: Rendered

/// Where a hero's button goes. A menu section or a single dish — the server
/// refuses anything else, so there is no third case to defend against.
enum StorefrontTarget {
    case item(UUID)
    case section(UUID)

    var id: UUID {
        switch self {
        case .item(let id), .section(let id): return id
        }
    }
}

struct StorefrontHero {
    let id: String
    let headline: String
    let subheadline: String?
    let mediaURL: String?
    let ctaLabel: String?
    let ctaTarget: StorefrontTarget?
}

/// A rail of dishes. `featured` and `collection` differ only in emphasis and in
/// whether the title is guaranteed — one struct, because two identical views
/// with different names is how a design drifts.
struct StorefrontRail {
    let id: String
    let title: String?
    let itemIds: [UUID]
    let featured: Bool
}

struct StorefrontPromo {
    let id: String
    let promotionId: UUID
}

struct StorefrontText {
    let id: String
    let title: String?
    let body: String
}

struct StorefrontInfo {
    let id: String
    let title: String?
}

/// A block this build knows how to draw.
enum StorefrontBlock: Identifiable {
    case hero(StorefrontHero)
    case rail(StorefrontRail)
    case promo(StorefrontPromo)
    case text(StorefrontText)
    case info(StorefrontInfo)

    var id: String {
        switch self {
        case .hero(let block):  return block.id
        case .rail(let block):  return block.id
        case .promo(let block): return block.id
        case .text(let block):  return block.id
        case .info(let block):  return block.id
        }
    }

    /// Nil for a type this build can't draw — an unknown one from a newer
    /// server, or `media_row`, whose posts and videos need reads the delivery
    /// screen has no business making. Both are skipped the same way, which is
    /// the whole point of having one answer for "I don't know this block".
    static func from(_ dto: StorefrontBlockDTO) -> StorefrontBlock? {
        switch dto.type {
        case "hero":
            guard let headline = dto.headline, !headline.isEmpty else { return nil }
            return .hero(StorefrontHero(
                id: dto.id, headline: headline, subheadline: dto.subheadline,
                mediaURL: dto.mediaUrl, ctaLabel: dto.ctaLabel,
                ctaTarget: target(dto.ctaTarget)))
        case "featured_items", "collection":
            let ids = dto.itemIds ?? []
            guard !ids.isEmpty else { return nil }
            return .rail(StorefrontRail(id: dto.id, title: dto.title, itemIds: ids,
                                        featured: dto.type == "featured_items"))
        case "promo_banner":
            guard let promotionId = dto.promotionId else { return nil }
            return .promo(StorefrontPromo(id: dto.id, promotionId: promotionId))
        case "text":
            guard let body = dto.body, !body.isEmpty else { return nil }
            return .text(StorefrontText(id: dto.id, title: dto.title, body: body))
        case "info":
            return .info(StorefrontInfo(id: dto.id, title: dto.title))
        default:
            return nil
        }
    }

    static func page(_ dto: StorefrontDTO?) -> [StorefrontBlock] {
        (dto?.blocks ?? []).compactMap(StorefrontBlock.from)
    }

    private static func target(_ ref: StorefrontRefDTO?) -> StorefrontTarget? {
        guard let ref else { return nil }
        switch ref.kind {
        case "ITEM":    return .item(ref.id)
        case "SECTION": return .section(ref.id)
        default:        return nil
        }
    }
}
