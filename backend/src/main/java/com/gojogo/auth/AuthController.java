package com.gojogo.auth;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
class AuthController {

    private final ProfileApi profiles;
    private final AppleAuthService appleAuth;

    AuthController(ProfileApi profiles, AppleAuthService appleAuth) {
        this.profiles = profiles;
        this.appleAuth = appleAuth;
    }

    /**
     * Given a valid Cognito JWT, create-or-fetch the app-side profile row.
     * The email claim is present on Cognito ID tokens; access tokens carry only the sub.
     */
    @PostMapping("/v1/auth/session")
    SessionResponse establishSession(@AuthenticationPrincipal Jwt jwt) {
        ProfileDto profile = profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email"));
        return new SessionResponse(profile.id(), profile.cognitoSub(), profile.email(),
            profile.displayName(), profile.handle());
    }

    /**
     * Native Sign in with Apple. Validates Apple's identity token and returns a
     * Cognito token set; the client then calls {@code /v1/auth/session} as usual.
     * Public (no bearer token yet) — see SecurityConfig.
     */
    @PostMapping("/v1/auth/apple")
    TokenResponse appleSignIn(@Valid @RequestBody AppleSignInRequest request) {
        return appleAuth.exchange(request);
    }

    @ExceptionHandler(AppleAuthException.class)
    ResponseEntity<Map<String, String>> appleFailure(AppleAuthException e) {
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
            .body(Map.of("message", "Could not verify your Apple sign-in."));
    }
}
