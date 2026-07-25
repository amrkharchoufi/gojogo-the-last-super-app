package com.gojogo.economy.internal;

import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

/**
 * The wiping half of the dev-only cleanup surface. Deliberately separate from
 * {@link ListingService}: nothing here is part of the product, and dropping this
 * file plus {@link EconomyAdminController} removes the feature whole.
 *
 * <p>Deletes go through bulk JPQL rather than the entity graph — photos
 * ({@code economy.listing_media}) and saves ({@code economy.saved_listing}) both
 * hang off the listing with {@code ON DELETE CASCADE}, so the database clears
 * them. The uploaded images themselves stay in S3 until MediaCleanupJob's
 * orphan sweep gets to them.
 */
@Service
class ListingAdminService {

    /** Typed by hand into the request body, so a stray curl can't wipe a table. */
    private static final String CONFIRM_PHRASE = "PURGE";

    private final ListingRepository listings;

    ListingAdminService(ListingRepository listings) {
        this.listings = listings;
    }

    /** Everything in the marketplace, newest first — what to look at before
     *  purging, and how to check afterwards. */
    @Transactional(readOnly = true)
    List<AdminListingSummary> inventory(int limit) {
        return listings.everyListing(PageRequest.of(0, Math.clamp(limit, 1, 500))).stream()
            .map(l -> new AdminListingSummary(l.getId(), l.getSellerId(), l.getTitle(),
                l.getStatus().name(), l.getMedia().size(), l.getCreatedAt()))
            .toList();
    }

    @Transactional
    PurgeListingsResponse purge(PurgeListingsRequest request) {
        if (!CONFIRM_PHRASE.equals(request.confirm())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Set confirm to " + CONFIRM_PHRASE + " to delete listings");
        }
        boolean byIds = request.listingIds() != null && !request.listingIds().isEmpty();
        if (byIds && request.sellerId() != null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Pass listingIds or sellerId, not both");
        }
        int deleted;
        if (byIds) {
            deleted = listings.deleteByIdIn(request.listingIds());
        } else if (request.sellerId() != null) {
            deleted = listings.deleteBySellerId(request.sellerId());
        } else {
            deleted = listings.deleteEveryListing();
        }
        return new PurgeListingsResponse(deleted, listings.count());
    }
}
