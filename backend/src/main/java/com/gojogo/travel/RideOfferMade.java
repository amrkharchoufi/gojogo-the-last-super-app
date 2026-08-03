package com.gojogo.travel;

import java.util.UUID;

/**
 * A price landed on the negotiating table — a driver countered the rider's
 * fare, or the rider countered back at one driver.
 *
 * <p>Its own event rather than a {@link RideStatusChanged} status, because a
 * counteroffer does not move the ride's state machine (the ride merely sits in
 * NEGOTIATING) and it carries a fact no status does: the amount. The offer
 * lives about thirty seconds, which is why the push this becomes matters — the
 * person it is addressed to is not staring at the matching screen.
 *
 * @param recipientId who the price is addressed to: the rider for a driver's
 *                    counter, the driver for the rider's counter-back
 * @param fromName    who is asking, for the sentence on the lock screen
 */
public record RideOfferMade(UUID rideId, UUID recipientId, String fromName,
                            long amountMinor, String currency, int round) {
}
