package com.gojogo.auth;

/**
 * Who decided. {@code breakGlass} marks the shared-secret path — worth seeing in
 * a log line, because it is the one that can't name anybody.
 */
public record AdminActor(String who, boolean breakGlass) {

    @Override
    public String toString() {
        return breakGlass ? who : "admin " + who;
    }
}
