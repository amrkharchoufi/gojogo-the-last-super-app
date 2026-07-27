package com.gojogo.delivery;

import java.util.UUID;

/**
 * What an approved partner needs for a catalog entry to exist. A snapshot, not
 * a link: the merchant row keeps these values and the owner edits them in
 * delivery afterwards, so correcting a business name on the application never
 * silently renames a live restaurant.
 *
 * @param ownerId  the profile that will manage this restaurant
 * @param cuisine  the merchant's primary trade, as browse shows it
 * @param latitude / longitude where the kitchen is; null falls back to the
 *                 catalog default, since a courier route is simulated anyway
 *                 until Phase 3 dispatch
 */
public record MerchantRegistration(UUID ownerId, String name, String cuisine,
                                   String imageUrl, Double latitude, Double longitude) {
}
