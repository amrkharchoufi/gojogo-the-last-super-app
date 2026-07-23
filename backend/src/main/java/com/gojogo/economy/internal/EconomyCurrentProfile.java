package com.gojogo.economy.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

/**
 * Resolves the authenticated JWT to the app-side profile (creating it on first
 * touch, same as {@code /v1/auth/session}). Uniquely named per the incidents
 * log — two {@code @Component} classes sharing a simple name collide on the
 * default bean name across modules (see PROGRESS.md notifications deploy note).
 */
@Component
class EconomyCurrentProfile {

    private final ProfileApi profiles;

    EconomyCurrentProfile(ProfileApi profiles) {
        this.profiles = profiles;
    }

    ProfileDto require(Jwt jwt) {
        return profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email"));
    }
}
