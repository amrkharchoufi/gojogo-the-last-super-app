package com.gojogo.messaging.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

/**
 * Resolves the authenticated JWT to the app-side profile (creating it on first
 * touch), mirroring {@code social.internal.CurrentProfiles}.
 */
@Component
class CurrentProfile {

    private final ProfileApi profiles;

    CurrentProfile(ProfileApi profiles) {
        this.profiles = profiles;
    }

    ProfileDto require(Jwt jwt) {
        return profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email"));
    }
}
