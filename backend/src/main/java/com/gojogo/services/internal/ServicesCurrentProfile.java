package com.gojogo.services.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

/** JWT → app profile, uniquely named per the incidents log (two @Components
 *  sharing a simple name collide on the default bean name across modules). */
@Component
class ServicesCurrentProfile {

    private final ProfileApi profiles;

    ServicesCurrentProfile(ProfileApi profiles) {
        this.profiles = profiles;
    }

    ProfileDto require(Jwt jwt) {
        return profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email"));
    }
}
