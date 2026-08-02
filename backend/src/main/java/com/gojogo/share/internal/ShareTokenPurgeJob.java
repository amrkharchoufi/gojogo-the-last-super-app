package com.gojogo.share.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Drops share tokens long after they stopped working.
 *
 * <p>Not at expiry: a link that died an hour ago should still resolve to "this
 * trip is over" rather than to nothing, and only a row can say that. Once nobody
 * is plausibly still holding it, the row is a live-looking secret in a table
 * with no reason to exist.
 *
 * <p>Daily, in the same quiet window the media orphan sweep uses.
 */
@Component
class ShareTokenPurgeJob {

    private static final Logger log = LoggerFactory.getLogger(ShareTokenPurgeJob.class);

    private final ShareService share;

    ShareTokenPurgeJob(ShareService share) {
        this.share = share;
    }

    @Scheduled(cron = "${gojogo.share.purge-cron:0 45 3 * * *}")
    void tick() {
        try {
            int purged = share.purgeExpired();
            if (purged > 0) log.info("Purged {} expired share tokens", purged);
        } catch (RuntimeException e) {
            log.warn("Share token purge failed: {}", e.toString());
        }
    }
}
