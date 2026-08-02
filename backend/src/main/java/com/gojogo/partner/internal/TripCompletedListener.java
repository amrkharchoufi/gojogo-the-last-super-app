package com.gojogo.partner.internal;

import com.gojogo.travel.TripCompleted;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * The one place community verification is triggered from (Phase 3 M5).
 *
 * <p>{@code partner} listens to {@code travel} rather than {@code travel}
 * calling {@code partner}: a trip ending is a fact about a trip, and whether
 * that fact starts a vehicle check is entirely this module's business. Nothing
 * about the ride changes if the invitation is never created, which is why this
 * is an event and not a call.
 *
 * <p>{@code AFTER_COMMIT}, so an invitation is never created for a trip that
 * rolled back — and the work happens in a new transaction inside
 * {@link VehicleVerificationService#inviteFromTrip}, which is the part this
 * codebase has already paid to learn.
 */
@Component
class TripCompletedListener {

    private static final Logger log = LoggerFactory.getLogger(TripCompletedListener.class);

    private final VehicleVerificationService verifications;

    TripCompletedListener(VehicleVerificationService verifications) {
        this.verifications = verifications;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onTripCompleted(TripCompleted event) {
        try {
            verifications.inviteFromTrip(event.rideId(), event.riderId(),
                event.driverUserId(), event.vehicleId());
        } catch (RuntimeException e) {
            // Swallowed on purpose: the trip is over and paid for, and an
            // invitation that could not be created is a badge somebody does not
            // get. Throwing here would leave a completed ride looking failed.
            log.warn("Couldn't invite a verification after ride {}: {}",
                event.rideId(), e.toString());
        }
    }
}
