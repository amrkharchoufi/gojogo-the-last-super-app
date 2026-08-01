package com.gojogo.travel.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

/**
 * Resolves the authenticated JWT to the app-side profile. Uniquely named per the
 * incidents log — two {@code @Component} classes sharing a simple name collide
 * on the default bean name across modules.
 */
@Component
class TravelCurrentProfile {

    private final ProfileApi profiles;

    TravelCurrentProfile(ProfileApi profiles) {
        this.profiles = profiles;
    }

    ProfileDto require(Jwt jwt) {
        return profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email"));
    }
}
