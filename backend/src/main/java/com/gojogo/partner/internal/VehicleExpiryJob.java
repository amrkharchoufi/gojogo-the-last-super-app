package com.gojogo.partner.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * Takes cars off the road when their papers run out.
 *
 * <p>This is the only thing in the system that would ever notice. A registration
 * that lapsed in March is not a registration, and without a sweep the driver goes
 * on receiving work indefinitely because the day nothing happened is not an event
 * anything reacts to. A grace period (**CONFIG**, 7 days) is deliberate: renewals
 * are slow, people are on holiday, and cutting somebody's income off on the exact
 * midnight a certificate expires would be a policy nobody could defend.
 *
 * <p>Hourly rather than per-minute, because the unit here is a day. Every
 * decision is re-derived from the row inside its own transaction — a driver may
 * have uploaded a new certificate in the seconds since the sweep listed them.
 */
@Component
class VehicleExpiryJob {

    private static final Logger log = LoggerFactory.getLogger(VehicleExpiryJob.class);
    private static final int BATCH = 200;

    private final VehicleService vehicles;
    private final PartnerService partners;
    private final VehicleRepository repository;

    VehicleExpiryJob(VehicleService vehicles, PartnerService partners,
                     VehicleRepository repository) {
        this.vehicles = vehicles;
        this.partners = partners;
        this.repository = repository;
    }

    @Scheduled(fixedDelayString = "${gojogo.partner.vehicle-expiry-poll-ms:3600000}",
        initialDelayString = "${gojogo.partner.vehicle-expiry-initial-delay-ms:120000}")
    void tick() {
        for (UUID vehicleId : vehicles.lapsedVehicleIds(BATCH)) {
            try {
                if (!vehicles.flagIfStillLapsed(vehicleId)) continue;
                // It was the active one, so its driver is now unroadworthy.
                // Suspending is what actually stops the work; flagging alone
                // only changes a badge.
                repository.findById(vehicleId)
                    .flatMap(v -> partners.accountOfVehicleOwner(v.getAccountId()))
                    .ifPresent(account -> partners.suspendForVehicle(account,
                        "Your vehicle's registration or insurance has expired — "
                            + "upload a current one and we'll put you back on."));
                log.info("Vehicle {} flagged for expired papers; its driver was suspended",
                    vehicleId);
            } catch (RuntimeException e) {
                log.warn("Vehicle expiry sweep failed for {}: {}", vehicleId, e.toString());
            }
        }
    }
}
