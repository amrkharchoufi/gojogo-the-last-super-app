package com.gojogo.services;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Published when a provider creates or edits a service — one of the
 * index-source events SPECS §13 names. Consumed by search (Phase 5 M4).
 */
public record ServiceUpserted(UUID serviceId, UUID providerId, String name,
                              String category, boolean active, OffsetDateTime at) {
}
