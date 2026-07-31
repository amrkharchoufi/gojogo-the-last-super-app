package com.gojogo.storefront;

import java.util.Set;

/**
 * Which kind of page a document is, and therefore which blocks it may contain.
 *
 * <p>The surface is half the primary key — one owner id can legitimately have a
 * restaurant storefront and a business home page, and they are different pages
 * belonging to different modules.
 *
 * <p>The allow-lists are the reason this enum exists rather than a boolean.
 * A {@code collection} of menu items on a brand's home page is a block whose
 * ids nobody can resolve; a {@code promo_banner} there points at a promotion
 * table the profile module doesn't have. Refusing them at the write is how the
 * renderer stays free of "this block is only sometimes meaningful" branches.
 */
public enum StorefrontSurface {

    /**
     * A merchant's page in a vertical's catalog — {@code delivery.merchant}
     * today, {@code economy} and {@code services} on the same contract later.
     * Everything is allowed: this is the surface with a catalog behind it.
     */
    MERCHANT_STOREFRONT(Set.of(
        StorefrontBlockType.HERO,
        StorefrontBlockType.FEATURED_ITEMS,
        StorefrontBlockType.COLLECTION,
        StorefrontBlockType.PROMO_BANNER,
        StorefrontBlockType.MEDIA_ROW,
        StorefrontBlockType.TEXT,
        StorefrontBlockType.INFO)),

    /**
     * A business profile's home page (2e M1's "brand before commerce"). No
     * catalog blocks: a business profile that has never been through KYC has
     * nothing to sell, and one that has sells it through the vertical's own
     * storefront rather than through a second copy here.
     */
    BUSINESS_HOME(Set.of(
        StorefrontBlockType.HERO,
        StorefrontBlockType.MEDIA_ROW,
        StorefrontBlockType.TEXT,
        StorefrontBlockType.INFO));

    private final Set<StorefrontBlockType> allowed;

    StorefrontSurface(Set<StorefrontBlockType> allowed) {
        this.allowed = allowed;
    }

    public boolean allows(StorefrontBlockType type) {
        return allowed.contains(type);
    }

    public Set<StorefrontBlockType> allowedTypes() {
        return allowed;
    }
}
