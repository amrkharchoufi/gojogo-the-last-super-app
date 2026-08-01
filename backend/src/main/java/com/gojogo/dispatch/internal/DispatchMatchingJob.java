package com.gojogo.dispatch.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * The clock behind matching: widens searches ring by ring, and closes offers
 * nobody answered.
 *
 * <p>A poller rather than a timer per request, for the same reason delivery's
 * fulfilment job is one. Every decision is recomputed from the row, so a missed
 * run, a restart or a slow deploy catches up instead of leaving a rider watching
 * a wave that was scheduled inside a process which has since died. Two tasks
 * running it is fine — the loser of a race gets an optimistic-lock failure and
 * reads whatever the winner wrote on the next tick.
 */
@Component
class DispatchMatchingJob {

    private static final Logger log = LoggerFactory.getLogger(DispatchMatchingJob.class);
    private static final int BATCH = 200;

    private final DispatchService dispatch;

    DispatchMatchingJob(DispatchService dispatch) {
        this.dispatch = dispatch;
    }

    @Scheduled(fixedDelayString = "${gojogo.dispatch.matching-poll-ms:5000}")
    void tick() {
        for (UUID jobId : dispatch.jobsNeedingAttention(BATCH)) {
            try {
                dispatch.advance(jobId);
            } catch (OptimisticLockingFailureException anotherInstanceGotThere) {
                // Expected with more than one task; the next tick re-reads.
            } catch (RuntimeException e) {
                log.warn("Dispatch wave failed for job {}: {}", jobId, e.toString());
            }
        }
        try {
            dispatch.expireLapsedOffers(BATCH);
        } catch (RuntimeException e) {
            log.warn("Dispatch offer expiry sweep failed: {}", e.toString());
        }
    }
}
