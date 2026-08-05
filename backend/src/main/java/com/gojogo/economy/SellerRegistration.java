package com.gojogo.economy;

import java.util.UUID;

/**
 * What {@code partner} hands over when a SELLER approval provisions — the same
 * minimal shape as {@code delivery.MerchantRegistration}: who owns the shop and
 * how it introduces itself. Everything else is the owner's to configure.
 */
public record SellerRegistration(UUID ownerUserId, String displayName, String logoUrl) {
}
