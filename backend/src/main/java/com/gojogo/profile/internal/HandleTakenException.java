package com.gojogo.profile.internal;

import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

class HandleTakenException extends ResponseStatusException {

    HandleTakenException(String handle) {
        super(HttpStatus.CONFLICT, "Handle already taken: " + handle);
    }
}
