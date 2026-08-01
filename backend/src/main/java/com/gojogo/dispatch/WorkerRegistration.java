package com.gojogo.dispatch;

import java.util.UUID;

/**
 * What an approved partner needs for a dispatch registration to exist — the
 * driver/courier twin of {@code delivery.MerchantRegistration}, and just as
 * thin.
 *
 * @param userId           the profile that will be offered work
 * @param partnerAccountId the application that earned it, kept for the audit
 *                         trail; dispatch never reads back into {@code partner}
 * @param category         what they will be driving, or null for the default for
 *                         their kind. Null is the honest answer until Phase 3 M2
 *                         registers vehicles: an approval today knows a person is
 *                         allowed to drive, not what they drive
 * @param homeRegion       the city on the application, for later regional policy
 * @param vehicleLabel     "White Dacia Logan", and {@code vehiclePlate} beside
 *                         it. Pushed down rather than read across: the vehicle
 *                         lives in {@code partner} and a rider on a kerb needs to
 *                         know which car is theirs, so the fact travels in the
 *                         direction provisioning already goes
 */
public record WorkerRegistration(UUID userId, UUID partnerAccountId,
                                 VehicleCategory category, String homeRegion,
                                 String vehicleLabel, String vehiclePlate) {
}
