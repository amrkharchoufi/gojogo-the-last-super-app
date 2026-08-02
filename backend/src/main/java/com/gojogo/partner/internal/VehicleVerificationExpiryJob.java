package com.gojogo.partner.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.UUID;

/**
 * Closes verification invitations nobody answered.
 *
 * <p>Without it a vehicle asks one passenger and then waits forever: the check
 * for "is an invitation still out" would keep finding a row that lapsed weeks
 * ago, so the next passenger is never asked and the car never gets its badge.
 * The sweep is what makes falling through to the next trip work.
 *
 * <p>Marking one is deliberately <em>not</em> a rejection. Silence is not an
 * accusation — a passenger who never opened the app has said nothing about the
 * car, and flagging on that would take drivers off the road for having busy
 * customers.
 */
@Component
class VehicleVerificationExpiryJob {

    private static final Logger log = LoggerFactory.getLogger(VehicleVerificationExpiryJob.class);
    private static final int BATCH = 200;

    private final VehicleVerificationService verifications;

    VehicleVerificationExpiryJob(VehicleVerificationService verifications) {
        this.verifications = verifications;
    }

    @Scheduled(fixedDelayString = "${gojogo.partner.verification-expiry-poll-ms:1800000}",
        initialDelayString = "${gojogo.partner.verification-expiry-initial-delay-ms:180000}")
    void tick() {
        List<UUID> lapsed = verifications.lapsedInvitationIds(BATCH);
        for (UUID id : lapsed) {
            try {
                verifications.expireIfStillOpen(id);
            } catch (RuntimeException e) {
                log.warn("Couldn't expire verification {}: {}", id, e.toString());
            }
        }
        if (!lapsed.isEmpty()) {
            log.info("Expired {} unanswered vehicle verifications", lapsed.size());
        }
    }
}
