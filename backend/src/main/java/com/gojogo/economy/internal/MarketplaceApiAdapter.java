package com.gojogo.economy.internal;

import com.gojogo.economy.MarketplaceApi;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * {@link MarketplaceApi} over {@link ListingService} — the same decoration and
 * the same block/takedown rules the buyer's own grid runs through.
 */
@Component
class MarketplaceApiAdapter implements MarketplaceApi {

    private final ListingService listings;

    MarketplaceApiAdapter(ListingService listings) {
        this.listings = listings;
    }

    @Override
    public List<Listing> listingsByIds(UUID viewerId, List<UUID> listingIds) {
        return listings.byIds(viewerId, listingIds).stream()
            .map(MarketplaceApiAdapter::toListing)
            .toList();
    }

    @Override
    public Optional<Listing> listing(UUID viewerId, UUID listingId) {
        try {
            return Optional.of(toListing(listings.get(viewerId, listingId)));
        } catch (org.springframework.web.server.ResponseStatusException notFound) {
            // The controller's 404 is right for a browser. In-process, a caller
            // decides for itself what a listing it cannot see means.
            return Optional.empty();
        }
    }

    private static Listing toListing(ListingResponse r) {
        return new Listing(r.id(), r.title(), r.priceCents(), r.currency(), r.category(),
            r.condition(), r.locationLabel(), r.description(),
            r.seller() == null ? null : r.seller().handle(), r.status());
    }
}
