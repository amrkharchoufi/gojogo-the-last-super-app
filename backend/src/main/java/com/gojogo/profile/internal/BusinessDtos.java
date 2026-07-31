package com.gojogo.profile.internal;

import com.gojogo.storefront.StorefrontBlock;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.util.List;
import java.util.UUID;

/**
 * A business profile as its owner and the app see it: the profile half and the
 * business half in one payload, because to everyone outside this module they
 * are one identity.
 */
record BusinessProfileResponse(UUID id, String handle, String displayName, String bio,
                               String category, String avatarUrl,
                               UUID ownerProfileId, boolean verified,
                               String contactPhone, String contactEmail, String websiteUrl,
                               String addressLine, String city, String country,
                               Double latitude, Double longitude, String openingHours) {
}

/**
 * A whole home page, replacing whatever was there. Null or absent blocks clear
 * it — see the merchant storefront's twin, and for the same reason: a page is an
 * ordered list, so it is written whole.
 */
record SaveHomeRequest(@Size(max = 100) List<StorefrontBlock> blocks) {
}

/** Only the name is required — a brand can exist before its details do. */
record CreateBusinessRequest(@NotBlank @Size(max = 120) String displayName,
                             @Size(max = 60) String handle,
                             @Size(max = 60) String category,
                             @Size(max = 600) String bio,
                             @Size(max = 600) String avatarUrl,
                             @Size(max = 32) String contactPhone,
                             @Size(max = 160) String contactEmail,
                             @Size(max = 400) String websiteUrl,
                             @Size(max = 200) String addressLine,
                             @Size(max = 80) String city,
                             @Size(max = 60) String country,
                             Double latitude, Double longitude,
                             @Size(max = 4000) String openingHours) {
}

/** PATCH semantics: a null field means unchanged, not cleared. */
record UpdateBusinessRequest(@Size(max = 120) String displayName,
                             @Size(max = 60) String handle,
                             @Size(max = 60) String category,
                             @Size(max = 600) String bio,
                             @Size(max = 600) String avatarUrl,
                             @Size(max = 32) String contactPhone,
                             @Size(max = 160) String contactEmail,
                             @Size(max = 400) String websiteUrl,
                             @Size(max = 200) String addressLine,
                             @Size(max = 80) String city,
                             @Size(max = 60) String country,
                             Double latitude, Double longitude,
                             @Size(max = 4000) String openingHours) {
}
