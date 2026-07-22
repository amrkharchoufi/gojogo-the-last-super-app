package com.gojogo.social.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

/**
 * Resolves the authenticated JWT to the app-side profile (creating it on
 * first touch, same as /v1/auth/session, so call order doesn't matter).
 */
@Component
class CurrentProfiles {

    private final ProfileApi profiles;

    CurrentProfiles(ProfileApi profiles) {
        this.profiles = profiles;
    }

    ProfileDto require(Jwt jwt) {
        return profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email"));
    }
}
