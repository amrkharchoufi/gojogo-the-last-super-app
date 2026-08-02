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
 * @param vehicle          what they will be driving — pushed down rather than
 *                         read across, because the vehicle lives in
 *                         {@code partner} and a rider on a kerb needs to know
 *                         which car is theirs. {@link VehicleRef#none()} for
 *                         somebody with no vehicle at all, which is the honest
 *                         answer for a courier on a bicycle; a null category
 *                         inside it lets dispatch fall back to the default for
 *                         the kind
 * @param homeRegion       the city on the application, for later regional policy
 */
public record WorkerRegistration(UUID userId, UUID partnerAccountId, VehicleRef vehicle,
                                 String homeRegion) {

    public WorkerRegistration {
        vehicle = vehicle == null ? VehicleRef.none() : vehicle;
    }
}
