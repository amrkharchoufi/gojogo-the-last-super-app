package com.gojogo.dispatch.internal;

/**
 * What became of one offer.
 *
 * <p>{@link #WITHDRAWN} and {@link #EXPIRED} are kept apart on purpose. Both end
 * with the worker not doing the job, but only one of them is about the worker: a
 * lapsed offer says they ignored their phone, while a withdrawn one says
 * somebody else was quicker, and counting the second against an acceptance rate
 * would punish people for losing races they were never told about.
 */
enum OfferState {

    OFFERED,
    ACCEPTED,
    DECLINED,
    EXPIRED,
    WITHDRAWN;

    boolean isOpen() {
        return this == OFFERED;
    }
}
