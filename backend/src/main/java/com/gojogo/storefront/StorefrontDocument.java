package com.gojogo.storefront;

import java.time.OffsetDateTime;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * A whole storefront: {@code {version, blocks}} (SPECS.md §9), plus when it was
 * last written.
 *
 * <p><strong>Version is a counter, not a schema number.</strong> It starts at 0
 * for a page nobody has ever arranged and goes up by one on every save. A client
 * uses it to know whether the copy it cached is stale; a page builder uses it to
 * notice that someone else saved underneath it. It says nothing about the block
 * format — that moves by {@link StorefrontBlockType} gaining members.
 *
 * <p>{@link #empty()} is what every owner has until they arrange something, and
 * it is deliberately a document rather than a null: the merchant payload always
 * carries a storefront, so the app has one code path and an un-arranged
 * restaurant renders exactly the page it rendered before this milestone.
 */
public record StorefrontDocument(int version, List<StorefrontBlock> blocks,
                                 OffsetDateTime updatedAt) {

    public StorefrontDocument {
        blocks = blocks == null ? List.of() : List.copyOf(blocks);
    }

    /** Never arranged. Version 0 is the one version no save can produce. */
    public static StorefrontDocument empty() {
        return new StorefrontDocument(0, List.of(), null);
    }

    public boolean isEmpty() {
        return blocks.isEmpty();
    }

    /**
     * Every id of one kind used anywhere in the document, de-duplicated and in
     * document order — what a vertical checks ownership of before a save.
     */
    public Set<UUID> references(StorefrontRefKind kind) {
        Set<UUID> ids = new LinkedHashSet<>();
        for (StorefrontBlock block : blocks) {
            if (kind == StorefrontRefKind.ITEM && block.itemIds() != null) {
                block.itemIds().stream().filter(java.util.Objects::nonNull).forEach(ids::add);
            }
            if (kind == StorefrontRefKind.PROMOTION && block.promotionId() != null) {
                ids.add(block.promotionId());
            }
            if (block.ctaTarget() != null && block.ctaTarget().kind() == kind
                && block.ctaTarget().id() != null) {
                ids.add(block.ctaTarget().id());
            }
            if (block.media() != null) {
                block.media().stream()
                    .filter(ref -> ref != null && ref.kind() == kind && ref.id() != null)
                    .forEach(ref -> ids.add(ref.id()));
            }
        }
        return ids;
    }
}
