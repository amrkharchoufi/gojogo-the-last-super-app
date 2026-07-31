package com.gojogo.storefront;

import java.util.Optional;

/**
 * The closed set of blocks a storefront can be built from (SPECS.md §9).
 *
 * <p>Wire names are lower_snake because the document is authored by a page
 * builder and read by two clients, and {@code "featured_items"} survives being
 * looked at in a JSON viewer better than {@code "FEATURED_ITEMS"} does. The enum
 * is what everything server-side switches on.
 *
 * <p>Adding a member is the forward-compatibility mechanism: old clients skip a
 * block type they don't recognise, and the server keeps accepting every
 * document written before it existed.
 */
public enum StorefrontBlockType {

    /** A banner: image, headline, and optionally one button that goes somewhere. */
    HERO("hero"),

    /** A rail of catalog items the owner wants seen first. */
    FEATURED_ITEMS("featured_items"),

    /** A titled group of catalog items — "Ramadan menu", "Under $10". */
    COLLECTION("collection"),

    /** One promotion, rendered as the offer it is rather than as ad copy the
     *  owner has to keep in sync with the actual discount. */
    PROMO_BANNER("promo_banner"),

    /** Existing posts and videos, imported rather than re-uploaded — Studio's
     *  "use what you already published". */
    MEDIA_ROW("media_row"),

    /** Prose: an about section, allergen notes, a returns policy. */
    TEXT("text"),

    /**
     * Hours, delivery and pickup — <em>rendered from live data</em>, never
     * copied into the document. A block that duplicated opening hours would be
     * wrong the first Sunday the owner changed them and right nowhere.
     */
    INFO("info");

    private final String wire;

    StorefrontBlockType(String wire) {
        this.wire = wire;
    }

    /** The name this type has in JSON. */
    public String wire() {
        return wire;
    }

    /** Empty for a type this build has never heard of — the caller turns that
     *  into a 400 that names it, rather than a deserialization failure. */
    public static Optional<StorefrontBlockType> of(String wire) {
        if (wire == null) {
            return Optional.empty();
        }
        String normalized = wire.trim().toLowerCase();
        for (StorefrontBlockType type : values()) {
            if (type.wire.equals(normalized)) {
                return Optional.of(type);
            }
        }
        return Optional.empty();
    }
}
