package com.gojogo.travel;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * The read side of the ride-hailing vertical, for other modules.
 *
 * <p>Travel's first facade, added for Madeleine's {@code quote_ride} and
 * {@code get_ride_status} tools (MADELEINE.md §5). Both verbs are reads on
 * purpose: quoting never opens a negotiation and never holds a driver, and
 * everything that does — requesting, accepting an offer, cancelling — is gated
 * (§5) and stays behind {@code /v1/travel} with the rider's own identity on it.
 * There is deliberately no write verb here to add one to.
 *
 * <p><b>Coordinates, not place names.</b> This platform has no geocoder, and
 * the fare comes from a route between two points. A caller holding free text
 * has to resolve it to a point first — from the user's own saved addresses, or
 * from a map the user tapped — and a caller that cannot resolve it must say so
 * rather than guess, because a fare quoted for the wrong pickup is worse than
 * no fare.
 */
public interface TravelApi {

    /**
     * Every vehicle category priced for one route, the same numbers the picker
     * shows. Empty categories mean the pricing table has no effective row —
     * a real state, not an error.
     */
    Quote quote(double pickupLatitude, double pickupLongitude,
                double dropoffLatitude, double dropoffLongitude);

    /**
     * The caller's live ride, from whichever side of it they are on, or empty
     * when they are not in one. Falls back to their most recent finished trip
     * only if {@code includeRecent} — "where's my driver" and "how was my last
     * trip" are different questions and a caller should say which it is asking.
     */
    Optional<Ride> currentRide(UUID userId, boolean includeRecent);

    record Quote(long distanceMetres, long durationSeconds, String currency,
                 List<QuotedCategory> categories) {
    }

    /** @param minimumMinor the floor a negotiation may not go under */
    record QuotedCategory(String category, long suggestedFareMinor, long minimumMinor) {
    }

    /**
     * A trip as its rider sees it.
     *
     * @param agreedFareMinor  null until a fare is frozen; the negotiation is
     *                         still open until then
     * @param driverName       the other party, or null before anyone took it
     * @param durationSeconds  the estimated <em>trip</em> length from the route,
     *                         which is not how long until the car arrives.
     *                         Nothing stores that second number, so nothing here
     *                         reports it — a made-up "4 minutes away" is exactly
     *                         the kind of fact a caller would repeat to a person
     *                         standing on a street
     */
    record Ride(UUID id, String state, String category, String pickupLabel, String dropoffLabel,
                long suggestedFareMinor, Long agreedFareMinor, String currency,
                String driverName, String vehicleLabel,
                int distanceMetres, int durationSeconds) {
    }
}
