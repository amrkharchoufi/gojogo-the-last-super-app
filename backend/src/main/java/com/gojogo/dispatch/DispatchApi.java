package com.gojogo.dispatch;

import java.util.Optional;
import java.util.Set;
import java.util.UUID;

/**
 * What a vertical may ask of dispatch. Five verbs, and none of them mention
 * money, fares or baskets.
 *
 * <p>The shape is deliberately asymmetric: a vertical <em>calls</em> to start,
 * cancel and finish a search, and <em>listens</em> for the outcome
 * ({@link DispatchAssigned}, {@link DispatchExhausted}). Matching takes waves and
 * seconds, so there is nothing sensible for a synchronous call to return.
 */
public interface DispatchApi {

    /**
     * Starts looking for somebody, or returns the id of the search already
     * running for this job. Idempotent on {@code (jobKind, jobRefId)} — a
     * retried call, a replayed message and a double-tapped button all find the
     * same search, because offering one trip to two sets of drivers is a bug
     * that is invisible until two of them arrive.
     */
    UUID request(DispatchRequest request);

    /**
     * Stops the search, or releases the worker if one had already accepted.
     * Safe to call for a job dispatch has never heard of — a vertical
     * cancelling an order that never reached dispatch should not have to know
     * that.
     *
     * @param workerAtFault whether this counts against the worker's record. The
     *                      caller knows; dispatch cannot tell a rider who
     *                      changed their mind from a driver who drove off
     */
    void cancel(JobKind jobKind, UUID jobRefId, boolean workerAtFault);

    /**
     * The work is done. Frees the worker for the next offer and, if the customer
     * rated them, folds that in.
     *
     * @param rating 1–5, or null if the customer did not rate. Deliberately not
     *               defaulted to 5: an unrated job is not a perfect one
     */
    void complete(JobKind jobKind, UUID jobRefId, Integer rating);

    /** Who is doing this job, if anybody is yet. */
    Optional<Assignment> assignmentFor(JobKind jobKind, UUID jobRefId);

    /** Where a worker last reported being — the live half of a tracking screen. */
    Optional<WorkerPosition> positionOf(UUID workerId);

    /**
     * Which dispatch registries this account holds. Read by {@code /v1/me/roles}
     * so "am I a driver" is answered by the registry rather than inferred from
     * an approval, which is what SPECS §8 means by roles being derived.
     */
    Set<WorkerKind> rolesOf(UUID userId);
}
