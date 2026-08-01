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
     * The vertical has decided who, and dispatch records it.
     *
     * <p>Added in Phase 3 M3, for the one case {@link #request} cannot cover: a
     * <b>negotiated</b> job. Dispatch's offer book asks "will you do this", which
     * a driver who wants a different fare has to answer <em>no</em> to — so the
     * price conversation that follows happens entirely in {@code travel}, and
     * when the rider accepts a counter there is no open dispatch offer left to
     * accept. This is how that ends: the vertical names the winner.
     *
     * <p>It does not weaken the first-accept-wins rule. The job row is still the
     * arbiter — assigning one that is already assigned throws, so a rider
     * accepting a counter a second after somebody took the job at the asking
     * price loses, exactly as a second driver would.
     *
     * @throws org.springframework.web.server.ResponseStatusException 409 if the
     *         job is already assigned, closed, or the worker is busy
     */
    Assignment assign(JobKind jobKind, UUID jobRefId, UUID workerId);

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

    /**
     * Was this account offered this job, and if so, which registration answered?
     *
     * <p>The narrowest question a negotiating vertical can ask, and deliberately
     * the only one. {@code travel} has to know that a driver posting a counter is
     * somebody dispatch actually put the trip in front of — otherwise any driver
     * in the city could bid on any ride — and it needs their worker id to assign
     * them if the rider says yes. Both answers in one call, and nothing else
     * disclosed.
     *
     * <p>It answers for a <em>closed</em> offer too, which is the point: a
     * counteroffer <b>is</b> a decline of the dispatch offer, so by the time the
     * price conversation happens the row is no longer open. Requiring it to be
     * would make negotiation impossible.
     */
    Optional<UUID> offeredWorkerId(JobKind jobKind, UUID jobRefId, UUID userId);
}
