package com.gojogo.auth;

/**
 * Cognito token set returned to the client after a native Apple sign-in.
 * Mirrors the shape the app already handles for email/Google tokens.
 */
record TokenResponse(String idToken, String accessToken, String refreshToken, int expiresIn) {
}
