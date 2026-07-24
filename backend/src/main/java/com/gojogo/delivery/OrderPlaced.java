package com.gojogo.delivery;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Published in-process when a customer places a delivery order. No consumer yet
 * — mirrors {@code social.PostCreated} / {@code economy.ListingCreated}; the
 * intended ones are order push notifications and analytics.
 */
public record OrderPlaced(UUID orderId, UUID userId, UUID merchantId, String merchantName,
                          long totalCents, String currency, OffsetDateTime placedAt) {
}
