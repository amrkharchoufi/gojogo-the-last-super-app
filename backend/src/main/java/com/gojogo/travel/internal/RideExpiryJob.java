package com.gojogo.travel.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * Ends requests nobody took, and prices nobody answered.
 *
 * <p>A poller for the same reason delivery's and dispatch's are: every decision
 * is recomputed from the row, so a restart or a slow deploy catches up rather
 * than leaving somebody watching a spinner for a request that died with a
 * process. Faster than dispatch's, because the thing being timed here is a
 * person standing on a street.
 */
@Component
class RideExpiryJob {

    private static final Logger log = LoggerFactory.getLogger(RideExpiryJob.class);
    private static final int BATCH = 200;

    private final RideService rides;

    RideExpiryJob(RideService rides) {
        this.rides = rides;
    }

    @Scheduled(fixedDelayString = "${gojogo.travel.expiry-poll-ms:5000}")
    void tick() {
        try {
            rides.expireLapsedOffers(BATCH);
        } catch (RuntimeException e) {
            log.warn("Ride offer expiry sweep failed: {}", e.toString());
        }
        for (UUID rideId : rides.expiredRideIds(BATCH)) {
            try {
                rides.expireIfStillOpen(rideId);
            } catch (RuntimeException e) {
                log.warn("Ride {} could not be expired: {}", rideId, e.toString());
            }
        }
    }
}
