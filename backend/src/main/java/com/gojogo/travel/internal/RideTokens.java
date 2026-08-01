package com.gojogo.travel.internal;

import java.util.Comparator;
import java.util.List;

/**
 * Picking the band a trip falls in — the whole of the token price, as a pure
 * function.
 *
 * <p>Kept away from anything that touches a database for the same reason
 * {@link Fares} is: nothing on the build machine can execute SQL, and "what did
 * this cost the driver" is not a number anybody should first see in production.
 * It is two lines of logic and every one of its failure modes is silent — an
 * unsorted list picks the wrong band, an off-by-one at a boundary charges a
 * three-kilometre trip as a long one, a missing catch-all makes the longest
 * trips free.
 */
final class RideTokens {

    private RideTokens() {
    }

    /** Trips up to {@code upToMetres} cost {@code tokens}. */
    record Band(int upToMetres, int tokens) {
    }

    /**
     * The cost of a trip of this length.
     *
     * <p><b>Inclusive at the top</b>: a band of 3000 covers a trip of exactly
     * 3000 metres. Boundaries have to fall somewhere, and the cheaper side is
     * the one to be wrong on — a driver charged a long-trip price for a trip
     * that was exactly at the line will notice, and be right.
     *
     * <p>Falls to <b>zero</b> when nothing covers the distance, rather than to
     * the most expensive band. A category whose price list is missing or whose
     * catch-all was deleted should stop charging, not start overcharging: the
     * first is a bug somebody reports, the second is one they leave over.
     */
    static int cost(List<Band> bands, long metres) {
        return bands.stream()
            .filter(band -> metres <= band.upToMetres())
            .min(Comparator.comparingInt(Band::upToMetres))
            .map(Band::tokens)
            .orElse(0);
    }

    /**
     * The cheapest ride this price list can produce — what "can this driver
     * afford to work at all" is measured against.
     *
     * <p>The minimum over every band rather than the first: nothing in the table
     * says a longer trip must cost more, and reading the shortest band as the
     * cheapest would be an assumption the schema does not enforce.
     */
    static int cheapest(List<Band> bands) {
        return bands.stream().mapToInt(Band::tokens).min().orElse(0);
    }
}
