import SwiftUI

// MARK: - Following a search result (Phase 5 · M4)
//
// A hit carries a kind and a `refId` in the *owning* module — search itself
// knows nothing about what a post or a service is, which is what keeps the
// module graph acyclic. So the tap-through lives here, on the one type that
// knows about all four surfaces.
//
// Every route is "fetch it, then open it" rather than "open a placeholder and
// fill it in". A hit is an index row, and an index row is by definition a copy
// of something that may since have been deleted — opening a page built out of
// the copy is how this app used to render listings that no longer existed.

extension AppState {

    func openSearchHit(_ hit: SearchHitDTO) {
        switch hit.searchKind {
        case .post:
            openPost(id: hit.refId)
        case .listing:
            activeTab = .economy
            economySegment = .marketplace
            openListing(id: hit.refId)
        case .product:
            activeTab = .economy
            economySegment = .shops
            openShopProduct(id: hit.refId)
        case .service:
            activeTab = .economy
            economySegment = .services
            openService(id: hit.refId)
        case .none:
            // A kind this build doesn't know: the index grew a constant before
            // the app did. Saying so beats a tap that does nothing.
            showEconomyNotice("That result needs a newer version of the app.")
        }
    }

    /// Opens a post the feed may never have loaded — a search hit is usually
    /// something you have not scrolled past. Same problem, and the same
    /// fetch-then-open, as a notification about a post from last week.
    private func openPost(id: UUID) {
        openPostSurface(id, comments: false)
    }
}
