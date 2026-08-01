package com.gojogo.dispatch;

import java.util.UUID;

/**
 * A veto on <em>offering</em> a particular job to a particular worker,
 * implemented by other modules and called by this one.
 *
 * <p>The direction is the point, and it is the third time this codebase has
 * needed it — {@code messaging.ConversationGuard} and
 * {@code moderation.ModeratableContent} are the same shape. Ride-hailing tokens
 * (SPECS §4) mean a driver who cannot pay for a job must not be sent it, and
 * SPECS says so plainly: such a driver "is filtered out by dispatch, not blocked
 * from the app". But dispatch must not learn what a token is. Its offer book
 * asks "will you do this job" and has no opinion about money — the same rule
 * that kept fare negotiation in {@code travel} in M3, and the reason this module
 * can serve two verticals at once.
 *
 * <p>So the rule is handed <em>down</em>: {@code travel} implements this,
 * dispatch collects whatever implementations exist and skips a candidate any of
 * them objects to. <b>A dispatch module with no implementations on the classpath
 * behaves exactly as it did before this interface existed</b> — everybody is
 * eligible — which is what keeps the module extractable.
 *
 * <p>It is asked <b>per job</b>, not per worker, because the answer depends on
 * the work: a three-kilometre ride and a thirty-kilometre one cost a driver
 * different numbers of tokens, and a single "can this person work" flag would
 * have to assume the worst and lock people out of trips they could afford.
 *
 * <p>Implementations are on the hot path of every wave. They must be cheap,
 * must not write, and must not throw — an implementation that fails is treated
 * as no objection, because a matching engine that stops finding drivers when a
 * vertical has a bad day is worse than one that occasionally offers a job that
 * is later refused.
 */
public interface WorkerEligibility {

    /**
     * @return null if there is no objection, otherwise a short sentence naming
     *         the reason. The sentence is for logs and for the vertical's own
     *         driver-facing surface — dispatch never shows it to the person who
     *         was skipped, because "you were not offered a job" is not an event
     *         it makes sense to notify anybody about
     */
    String refuseOffer(JobKind jobKind, UUID jobRefId, UUID workerUserId);
}
