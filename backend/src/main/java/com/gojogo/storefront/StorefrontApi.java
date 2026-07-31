package com.gojogo.storefront;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * How a vertical stores and serves the page its owners arrange.
 *
 * <p>Three verbs, and the asymmetry between them is the design: reads never
 * fail, writes are strict, and a write cannot be performed without handing over
 * the means to check its references.
 */
public interface StorefrontApi {

    /**
     * The owner's document, or {@link StorefrontDocument#empty()} — never null,
     * never an exception. A page that was written by a newer deploy and cannot
     * be parsed by this one also reads as empty: a restaurant with no decorative
     * header still sells food.
     */
    StorefrontDocument documentFor(StorefrontSurface surface, UUID ownerId);

    /**
     * Several owners at once, for a list screen. Owners with nothing arranged
     * are absent from the map rather than present with an empty document, so a
     * caller can tell "no storefront" from "not asked about".
     */
    Map<UUID, StorefrontDocument> documentsFor(StorefrontSurface surface, Set<UUID> ownerIds);

    /**
     * Validates and stores the document whole, as the next version.
     *
     * <p>Whole, not incrementally: a page is an ordered list, and a patch API
     * over an ordered list is a lock-free reordering problem nobody asked for.
     * The version returned is what the author holds to notice a concurrent save.
     *
     * @param references run before anything is written; see
     *                   {@link StorefrontReferenceCheck}
     * @throws org.springframework.web.server.ResponseStatusException 400 for an
     *         unknown block type, a type this surface doesn't accept, a missing
     *         or over-long property, a property the type has no meaning for, a
     *         duplicate block id, or too many blocks
     */
    StorefrontDocument save(StorefrontSurface surface, UUID ownerId,
                            List<StorefrontBlock> blocks, StorefrontReferenceCheck references);
}
