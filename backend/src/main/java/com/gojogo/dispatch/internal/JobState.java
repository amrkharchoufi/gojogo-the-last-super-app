package com.gojogo.dispatch.internal;

/** Where a search is. Terminal states close the row; nothing reopens one. */
enum JobState {

    SEARCHING,
    ASSIGNED,
    /** Every ring searched, or out of time. The vertical has been told. */
    EXHAUSTED,
    CANCELLED;

    boolean isOpen() {
        return this == SEARCHING;
    }
}
