package com.gojogo.dispatch;

import java.util.UUID;

/**
 * Nobody took it, and dispatch has stopped trying — every ring was searched, or
 * the request simply ran out of time.
 *
 * <p>Published as its own event rather than left as silence because "no driver
 * found" is a thing a rider has to be told, and a vertical that learned it by
 * timing out would have to guess how long to wait.
 *
 * @param workersOffered how many people saw it before it lapsed. Zero and
 *                       fourteen are different failures — one is "there is
 *                       nobody here", the other is "nobody wants this trip"
 */
public record DispatchExhausted(UUID jobId, JobKind jobKind, UUID jobRefId, int workersOffered) {
}
