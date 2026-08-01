package com.gojogo.profile.internal;

import com.gojogo.profile.ProfileDto;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/**
 * {@code POST /v1/auth/session} — given a valid Cognito JWT, create-or-fetch the
 * app-side profile row and hand back who the caller is.
 *
 * <p><b>The path says auth and the code says profile, deliberately.</b> This
 * endpoint lived in the {@code auth} module until 2e M5, when {@code auth} grew
 * {@code PlatformAdminApi} and {@code AccountAdminApi} — capabilities that
 * {@code profile} and {@code moderation} consume — and the old
 * {@code auth → profile} direction became half of a cycle. Moving the controller
 * rather than the URL is what makes it a compile-time change and not a client
 * one: every app build in the field keeps calling the same path.
 *
 * <p>The email claim is present on Cognito ID tokens; access tokens carry only
 * the subject, which is why {@code createOrFetch} tolerates a null email.
 */
@RestController
class SessionController {

    private final ProfileService profiles;

    SessionController(ProfileService profiles) {
        this.profiles = profiles;
    }

    @PostMapping("/v1/auth/session")
    SessionResponse establishSession(@AuthenticationPrincipal Jwt jwt) {
        ProfileDto profile = profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email"));
        return new SessionResponse(profile.id(), profile.cognitoSub(), profile.email(),
            profile.displayName(), profile.handle());
    }
}

record SessionResponse(UUID profileId, String cognitoSub, String email, String displayName,
                       String handle) {
}
