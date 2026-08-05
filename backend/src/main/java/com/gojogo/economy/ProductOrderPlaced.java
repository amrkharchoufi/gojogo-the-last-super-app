package com.gojogo.economy;

import java.util.UUID;

/**
 * A product checkout landed in a seller's queue. Carries the owner id so the
 * notifications module can push without a read into economy — the same shape as
 * {@code delivery.OrderPlaced}.
 */
public record ProductOrderPlaced(UUID orderId, UUID sellerId, UUID sellerOwnerId,
                                 UUID buyerId, int itemCount, long totalCents) {
}
