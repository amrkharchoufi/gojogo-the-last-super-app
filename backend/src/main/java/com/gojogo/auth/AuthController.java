package com.gojogo.auth;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
class AuthController {

    private final ProfileApi profiles;

    AuthController(ProfileApi profiles) {
        this.profiles = profiles;
    }

    /**
     * Given a valid Cognito JWT, create-or-fetch the app-side profile row.
     * The email claim is present on Cognito ID tokens; access tokens carry only the sub.
     */
    @PostMapping("/v1/auth/session")
    SessionResponse establishSession(@AuthenticationPrincipal Jwt jwt) {
        ProfileDto profile = profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email"));
        return new SessionResponse(profile.id(), profile.cognitoSub(), profile.email(), profile.displayName());
    }
}
