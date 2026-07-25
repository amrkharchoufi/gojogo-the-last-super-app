package com.gojogo.watch.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

/**
 * Resolves the authenticated JWT to the app-side profile, creating it on first
 * touch so call order never matters. Same shape as social's {@code
 * CurrentProfiles} — each module resolves its own rather than sharing one, so
 * neither reaches into the other's internals.
 */
@Component
class WatchCurrentProfile {

    private final ProfileApi profiles;

    WatchCurrentProfile(ProfileApi profiles) {
        this.profiles = profiles;
    }

    ProfileDto require(Jwt jwt) {
        return profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email"));
    }
}
