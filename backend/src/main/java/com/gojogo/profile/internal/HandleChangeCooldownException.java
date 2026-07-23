package com.gojogo.profile.internal;

import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;

/**
 * Thrown when a user tries to change their handle before the 2-month cooldown
 * has elapsed. 429 so the client can distinguish rate-limiting from a taken
 * handle (409). The reason is surfaced to the app as the {@code message} field.
 */
class HandleChangeCooldownException extends ResponseStatusException {

    HandleChangeCooldownException(OffsetDateTime availableAt) {
        super(HttpStatus.TOO_MANY_REQUESTS,
            "You can change your username again on "
                + availableAt.format(DateTimeFormatter.ISO_LOCAL_DATE) + ".");
    }
}
