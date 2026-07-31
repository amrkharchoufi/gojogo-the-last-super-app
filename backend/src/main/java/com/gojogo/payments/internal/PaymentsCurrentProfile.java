package com.gojogo.payments.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

/**
 * Resolves the authenticated JWT to the app-side profile. Uniquely named per the
 * incidents log — two {@code @Component} classes sharing a simple name collide
 * on the default bean name across modules.
 *
 * <p>Note what is <em>not</em> offered: acting as a business. A wallet belongs to
 * the person who signed in, and a business's money is the merchant's, reached
 * through the vertical that owns it. Letting the act-as header pick which wallet
 * to spend from would be a way to spend someone else's.
 */
@Component
class PaymentsCurrentProfile {

    private final ProfileApi profiles;

    PaymentsCurrentProfile(ProfileApi profiles) {
        this.profiles = profiles;
    }

    ProfileDto require(Jwt jwt) {
        return profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email"));
    }
}
