package com.gojogo.economy;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * The read side of the marketplace, for other modules.
 *
 * <p>{@link SellerProvisioningApi} is how a seller comes into existence; this
 * is how somebody who is not the buyer's phone asks what is for sale. Added for
 * Madeleine's {@code search_listings} / {@code get_listing} tools
 * (MADELEINE.md §5).
 *
 * <p><b>Every read takes a viewer.</b> A listing is not a public fact: a block
 * hides a seller's whole shelf from the person they blocked, and a moderator's
 * takedown hides a row from everyone except its author. Passing the viewer
 * through is what keeps those rules the module's own rather than something each
 * caller has to remember — and it is why there is no "find by id" without one.
 *
 * <p>Text search deliberately does <em>not</em> live here. The index is the
 * {@code search} module's ({@link com.gojogo.search.SearchQueryApi}, kind
 * {@code LISTING}); a caller searches there, gets ids, and hydrates them
 * through {@link #listingsByIds}. Growing a second query path over the same
 * rows is how two searches start disagreeing.
 */
public interface MarketplaceApi {

    /**
     * Listings by id, in the order given, with the viewer's visibility rules
     * applied — rows they may not see are absent rather than blanked, so the
     * caller cannot accidentally reveal that there was something there.
     */
    List<Listing> listingsByIds(UUID viewerId, List<UUID> listingIds);

    /**
     * One listing in full, or empty when it does not exist or this viewer may
     * not see it. Those two cases are deliberately indistinguishable — "you may
     * not see this" still confirms there is a this.
     */
    Optional<Listing> listing(UUID viewerId, UUID listingId);

    /**
     * @param priceMinor null for a listing with no asking price ("make me an
     *                   offer"), which is a real state and not a zero
     */
    record Listing(UUID id, String title, Long priceMinor, String currency, String category,
                   String condition, String locationLabel, String description,
                   String sellerHandle, String status) {
    }
}
