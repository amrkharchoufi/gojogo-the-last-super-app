package com.gojogo.assistant.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

/**
 * Resolves the authenticated JWT to the app-side profile, creating it on first
 * touch — the same as every other module's version of this.
 *
 * <p>Uniquely named per the incidents log: two {@code @Component} classes
 * sharing a simple name collide on the default bean name across modules.
 *
 * <p>This is also the whole of Madeleine's authority. The profile id it returns
 * is what every tool call runs as, so there is no route by which she could act
 * as anybody else — the identity is resolved once, from a token the caller
 * presented, and carried unchanged into every facade.
 */
@Component
class AssistantCurrentProfile {

    private final ProfileApi profiles;

    AssistantCurrentProfile(ProfileApi profiles) {
        this.profiles = profiles;
    }

    ProfileDto require(Jwt jwt) {
        return profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email"));
    }
}
