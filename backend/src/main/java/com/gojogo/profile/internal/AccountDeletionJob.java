package com.gojogo.profile.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Scrubs accounts whose grace period has run out.
 *
 * <p>Nightly, at an odd minute so it doesn't land on top of the media sweep
 * (03:30) or the ledger audit (03:17). A day's granularity is right for a
 * thirty-day promise: nobody is counting hours, and running it hourly would be
 * thirty times the chances of doing the irreversible thing during an incident.
 *
 * <p>Deliberately not catching up on a missed night by running more often — the
 * batch is worked oldest-first, so a backlog drains at 200 a night and the only
 * cost of a skipped run is that somebody's data survives one extra day.
 */
@Component
class AccountDeletionJob {

    private static final Logger log = LoggerFactory.getLogger(AccountDeletionJob.class);

    private final AccountDeletionService deletions;

    AccountDeletionJob(AccountDeletionService deletions) {
        this.deletions = deletions;
    }

    @Scheduled(cron = "0 5 4 * * *")
    void sweep() {
        try {
            int scrubbed = deletions.sweepDueDeletions();
            if (scrubbed > 0) {
                log.warn("Deletion sweep anonymized {} account(s)", scrubbed);
            }
        } catch (RuntimeException e) {
            // Never let a bad night take the scheduler down: the next run picks
            // up exactly the same rows, because nothing was marked.
            log.error("Deletion sweep failed", e);
        }
    }
}
