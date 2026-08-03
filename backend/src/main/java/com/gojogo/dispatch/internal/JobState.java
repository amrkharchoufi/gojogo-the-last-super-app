package com.gojogo.dispatch.internal;

/** Where a search is. Terminal states close the row; nothing reopens one. */
enum JobState {

    SEARCHING,
    ASSIGNED,
    /** The work was done. Closed as its own state rather than left ASSIGNED,
     *  because "current assignment" is answered by this column and a finished
     *  trip must stop being somebody's current anything. */
    COMPLETED,
    /** Every ring searched, or out of time. The vertical has been told. */
    EXHAUSTED,
    CANCELLED;

    boolean isOpen() {
        return this == SEARCHING;
    }
}
