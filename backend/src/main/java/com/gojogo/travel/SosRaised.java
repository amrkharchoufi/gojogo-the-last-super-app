package com.gojogo.travel;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/**
 * Somebody pressed SOS during a trip (Phase 3 M5, SPECS §10).
 *
 * <p>An event rather than a call because two things have to happen and neither
 * belongs to {@code travel}: {@code notifications} tells the people who need
 * telling, and an operator surface shows the trip. Making the button wait on
 * either of them would be the wrong trade — the ride row is written first, and
 * the alarm going out is a consequence rather than a precondition.
 *
 * <p>{@code contactProfileIds} are the emergency contacts who are <em>also</em>
 * GojoGo accounts, which is the only channel that can reach somebody without the
 * person in trouble doing anything else. The contacts who are just a phone
 * number are returned to the caller instead, with the message already written,
 * because the phone's own composer is the thing that can actually text them
 * today (PROGRESS "Needs YOU" #3).
 *
 * @param shareUrl the public tracking link, already minted. On the event so that
 *                 whatever sends the alert never has to know how one is made
 */
public record SosRaised(UUID rideId, UUID raisedBy, String raisedByName,
                        UUID riderId, UUID driverUserId, List<UUID> contactProfileIds,
                        String shareUrl, String pickupLabel, String dropoffLabel,
                        String vehicleLabel, String vehiclePlate,
                        Double latitude, Double longitude, OffsetDateTime at) {
}
