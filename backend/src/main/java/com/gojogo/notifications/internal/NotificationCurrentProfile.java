package com.gojogo.notifications.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

/**
 * Resolves the authenticated JWT to the app-side profile (creating on first
 * touch). Named distinctly from the messaging module's equivalent — both would
 * otherwise take the default bean name {@code currentProfile} and collide.
 */
@Component
class NotificationCurrentProfile {

    private final ProfileApi profiles;

    NotificationCurrentProfile(ProfileApi profiles) {
        this.profiles = profiles;
    }

    ProfileDto require(Jwt jwt) {
        return profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email"));
    }
}
