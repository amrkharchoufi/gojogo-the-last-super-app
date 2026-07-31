package com.gojogo.storefront;

/**
 * What a block points at. The kind travels with the id because this module has
 * no way to tell one UUID from another, and the vertical that checks the id
 * needs to know which of its tables to look in.
 */
public enum StorefrontRefKind {

    /** A catalog item — a dish today, a product in Phase 5. */
    ITEM,

    /** A section of the catalog, so a hero button can say "see the whole menu". */
    SECTION,

    /** A promotion of the owner's own. */
    PROMOTION,

    /** A social post. */
    POST,

    /** A Watch video, long-form or short. */
    VIDEO
}
