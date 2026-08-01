package com.gojogo.auth;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * What is left of auth's REST surface once {@code /v1/auth/session} moved to the
 * module that owns the row it creates (2e M5).
 *
 * <p>That move was forced and it was also right: {@code auth} exposing
 * {@link PlatformAdminApi} and {@link AccountAdminApi} means other modules —
 * {@code profile} and {@code moderation} among them — now depend on it, and
 * {@code auth} depending on {@code profile} in return was a cycle. Auth is a
 * layer over Cognito; knowing what a profile is was never its business.
 */
@RestController
class AuthController {

    private final AppleAuthService appleAuth;

    AuthController(AppleAuthService appleAuth) {
        this.appleAuth = appleAuth;
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
