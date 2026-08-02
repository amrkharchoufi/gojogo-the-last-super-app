package com.gojogo.partner;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * A passenger has been asked to confirm the car they just rode in (Phase 3 M5,
 * SPECS §4).
 *
 * <p>Published so {@code notifications} can turn it into a push, which is the
 * only thing that makes this mechanism work at all: a card sitting in an app
 * somebody has already closed is a card nobody answers, and an unanswered
 * invitation is a vehicle that never gets verified.
 *
 * <p>The reward is on the event because it is the reason to tap. "Confirm your
 * car and get $3" is a push people open; "we have a question" is not.
 *
 * @param driverName  first name only. The passenger is being asked whether the
 *                    person driving matched the app, and a push that names them
 *                    in full is a push that answers its own question
 */
public record VehicleVerificationInvited(UUID verificationId, UUID passengerId, UUID vehicleId,
                                         String driverName, String vehicleLabel,
                                         String vehiclePlate, long rewardMinor, String currency,
                                         OffsetDateTime expiresAt) {
}
