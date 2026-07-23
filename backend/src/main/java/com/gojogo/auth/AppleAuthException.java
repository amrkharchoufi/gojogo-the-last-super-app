package com.gojogo.auth;

/** Raised when a native Apple sign-in cannot be validated or exchanged. */
class AppleAuthException extends RuntimeException {
    AppleAuthException(String message) {
        super(message);
    }

    AppleAuthException(String message, Throwable cause) {
        super(message, cause);
    }
}
