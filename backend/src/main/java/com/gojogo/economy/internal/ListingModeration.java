package com.gojogo.economy.internal;

import com.gojogo.moderation.ModeratableContent;
import com.gojogo.moderation.ModerationAction;
import com.gojogo.moderation.ModerationTargetKind;
import org.springframework.stereotype.Component;

import java.util.Optional;
import java.util.UUID;

/**
 * The marketplace's moderation handler — see the {@code moderation} package docs
 * for why this lives here rather than there.
 *
 * <p>The summary carries the price, because on a marketplace the price is often
 * the report: a counterfeit at a tenth of retail and a scam at "on ask" both
 * read as ordinary listings without it.
 */
@Component
class ListingModeration implements ModeratableContent {

    private final ListingService listings;

    ListingModeration(ListingService listings) {
        this.listings = listings;
    }

    @Override
    public ModerationTargetKind kind() {
        return ModerationTargetKind.LISTING;
    }

    @Override
    public Optional<ModerationTarget> look(UUID targetId) {
        return listings.find(targetId).map(listing -> new ModerationTarget(
            listing.getSellerId(),
            listing.getTitle() + " · " + priceLabel(listing)
                + (listing.getDescription() == null || listing.getDescription().isBlank()
                    ? "" : " — " + listing.getDescription()),
            listing.isHidden()));
    }

    private static String priceLabel(Listing listing) {
        return listing.getPriceCents() == null
            ? "on ask"
            : listing.getCurrency() + " " + (listing.getPriceCents() / 100.0);
    }

    @Override
    public void apply(UUID targetId, ModerationAction action) {
        switch (action) {
            case HIDE -> listings.setHidden(targetId, true);
            case RESTORE -> listings.setHidden(targetId, false);
            case REMOVE -> listings.removeAsModerator(targetId);
            case SUSPEND -> throw new UnsupportedOperationException("Suspend acts on the account");
        }
    }
}
