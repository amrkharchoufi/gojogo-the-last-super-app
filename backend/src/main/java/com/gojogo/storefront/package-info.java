/**
 * Storefronts and profile home pages — the versioned block documents a business
 * arranges its own page out of ({@code storefront} schema, SPECS.md §9).
 *
 * <p>This is the write contract GoJoAdmin's Studio drives (ARCHITECTURE §10b).
 * It exists as a module rather than as a column on {@code delivery.merchant}
 * because a restaurant page, a shop page and a service provider's page are the
 * same document with different blocks allowed on it, and three verticals each
 * inventing their own JSON is three renderers that disagree by the second
 * release.
 *
 * <p><strong>The block set is closed, and closed per surface.</strong> A
 * document is a list of blocks from {@link com.gojogo.storefront.StorefrontBlockType},
 * and each {@link com.gojogo.storefront.StorefrontSurface} names the subset it
 * accepts — a menu {@code collection} means nothing on a personal brand's home
 * page, so the write refuses it rather than storing something no renderer will
 * ever draw. An unknown type is a <b>400 naming it</b>; forward compatibility is
 * a version bump on this enum plus the client's own skip-what-you-don't-know
 * discipline, not a free-form bag of properties.
 *
 * <p><strong>What this module validates, and what it deliberately doesn't.</strong>
 * It validates shape: known types, required properties, lengths, block counts,
 * reference kinds, and that no block carries a property its type has no meaning
 * for. It does <em>not</em> know whether menu item {@code 7f3…} exists or whose
 * it is — only {@code delivery} can answer that. So a write takes a
 * {@link com.gojogo.storefront.StorefrontReferenceCheck} from the calling
 * vertical and runs it before storing; there is no save that skips it, which is
 * the point of putting it in the signature rather than in a doc comment.
 *
 * <p><strong>A document that cannot be parsed reads as no storefront.</strong>
 * The read path never throws: a restaurant page that 500s because its decorative
 * header was written by a newer deploy is a worse outcome than a restaurant page
 * without a header. Writes are strict; reads are forgiving.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Storefront")
package com.gojogo.storefront;
