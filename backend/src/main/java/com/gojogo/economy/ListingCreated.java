package com.gojogo.economy;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Published in-process when a seller lists an item. First intended consumer is
 * the platform search index (OpenSearch) in Phase 2b — no consumer yet, mirrors
 * {@code social.PostCreated}.
 */
public record ListingCreated(UUID listingId, UUID sellerId, String title,
                             String category, OffsetDateTime createdAt) {
}
