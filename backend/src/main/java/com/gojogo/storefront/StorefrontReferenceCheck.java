package com.gojogo.storefront;

import java.util.Set;
import java.util.UUID;

/**
 * How a vertical proves the ids in a document are its own.
 *
 * <p>This module can validate that a block claims to point at an ITEM; only
 * {@code delivery} can say whether that item is on <em>this</em> restaurant's
 * menu. So the check is a parameter of
 * {@link StorefrontApi#save(StorefrontSurface, UUID, java.util.List, StorefrontReferenceCheck)}
 * rather than a convention — there is no save that forgets to do it.
 *
 * <p>Implementations throw (a 400 naming the offending id) rather than
 * returning a boolean, because "which id" is the only part of the answer the
 * author can act on.
 *
 * <p><strong>A kind the caller cannot check is passed over, deliberately.</strong>
 * {@code delivery} has no dependency on {@code social} or {@code watch}, so it
 * cannot say whether a POST id exists — and it doesn't need to: an imported
 * post renders through the same public read as anywhere else, so a borrowed id
 * shows content that was already public and a bogus one shows nothing. The
 * ownership rules worth enforcing are the ones about money and catalog, and
 * those all belong to a module that can enforce them.
 */
@FunctionalInterface
public interface StorefrontReferenceCheck {

    /** Nothing to check — the surface has no references its owner could forge. */
    StorefrontReferenceCheck NONE = (kind, ids) -> {
    };

    /**
     * Called once per {@link StorefrontRefKind} the document actually uses,
     * never with an empty set.
     *
     * @throws org.springframework.web.server.ResponseStatusException naming the
     *         first id that isn't the owner's
     */
    void check(StorefrontRefKind kind, Set<UUID> ids);
}
