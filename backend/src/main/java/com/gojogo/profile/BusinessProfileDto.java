package com.gojogo.profile;

import java.util.UUID;

/**
 * The extra a business profile carries beyond what every profile has. Name,
 * handle, bio, category and avatar are <em>not</em> here — a business has those
 * because it is a profile, and duplicating them would fork the two.
 *
 * @param verified earned through a partner approval (KYC'd), never bought
 */
public record BusinessProfileDto(
    UUID profileId,
    UUID ownerProfileId,
    String contactPhone,
    String contactEmail,
    String websiteUrl,
    String addressLine,
    String city,
    String country,
    Double latitude,
    Double longitude,
    String openingHours,
    boolean verified
) {
}
