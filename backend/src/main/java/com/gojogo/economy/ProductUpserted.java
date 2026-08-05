package com.gojogo.economy;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Published when a seller creates or edits a catalog product — one of the
 * index-source events SPECS §13 names. The search module consumes it (Phase 5
 * M4); nothing else should need to.
 */
public record ProductUpserted(UUID productId, UUID sellerId, String name,
                              String category, String brand, boolean active,
                              OffsetDateTime at) {
}
