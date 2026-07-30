package com.gojogo.economy.internal;

import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

/**
 * Where a listing is in its life. Only {@link #ACTIVE} listings appear in
 * browse; the other two stay visible to the seller (and to anyone who saved
 * the listing) so a sale isn't indistinguishable from a deletion.
 *
 * Public (though still in the internal package, so unreachable cross-module):
 * Spring Data's interface projection returns it through a JDK proxy, and the
 * proxy can't touch a package-private class — /mine/stats 500'd in prod.
 */
public enum ListingStatus {
    /** Live in the marketplace. */
    ACTIVE,
    /** Taken down by the seller, not sold — relisting is one tap. */
    PAUSED,
    /** Sold. Terminal as far as browse is concerned; kept for history. */
    SOLD;

    static ListingStatus parse(String raw) {
        if (raw == null || raw.isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Missing status");
        }
        try {
            return valueOf(raw.trim().toUpperCase(java.util.Locale.ROOT));
        } catch (IllegalArgumentException unknown) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Unknown status: " + raw);
        }
    }
}
