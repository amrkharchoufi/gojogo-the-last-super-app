package com.gojogo.auth;

import jakarta.validation.constraints.NotBlank;

/**
 * Body of {@code POST /v1/auth/apple}. The iOS app performs a native
 * ASAuthorizationController sign-in and forwards Apple's identity token here.
 *
 * @param identityToken Apple-signed JWT (its {@code aud} is the app bundle id).
 * @param rawNonce      the un-hashed nonce; the request set SHA-256(rawNonce) on
 *                      the Apple request, so the token's nonce claim must equal
 *                      the hash of this value.
 * @param fullName      display name, only sent on the very first authorization.
 */
record AppleSignInRequest(
    @NotBlank String identityToken,
    @NotBlank String rawNonce,
    String fullName) {
}
