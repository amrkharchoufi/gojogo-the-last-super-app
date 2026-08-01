package com.gojogo.travel.internal;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Which band a trip falls in.
 *
 * <p>Two lines of logic, and every way it goes wrong is silent: an unsorted list
 * picks the wrong row, a boundary off by one metre charges a short hop as a long
 * trip, a missing catch-all makes the longest and most expensive rides free.
 * None of those throws — the driver is simply charged the wrong number, on every
 * trip, until somebody notices.
 */
class RideTokenBandTests {

    /** The seeded shape: cheap short, dearer long, and a catch-all on the end. */
    private static final List<RideTokens.Band> CAR = List.of(
        new RideTokens.Band(3_000, 1),
        new RideTokens.Band(10_000, 2),
        new RideTokens.Band(2_000_000_000, 4));

    @Test
    @DisplayName("a trip lands in the cheapest band that still covers it")
    void picksTheCoveringBand() {
        assertThat(RideTokens.cost(CAR, 500)).isEqualTo(1);
        assertThat(RideTokens.cost(CAR, 4_200)).isEqualTo(2);
        assertThat(RideTokens.cost(CAR, 40_000)).isEqualTo(4);
    }

    @Test
    @DisplayName("a band is inclusive at the top — exactly 3000m is still the short band")
    void boundariesFallOnTheCheaperSide() {
        assertThat(RideTokens.cost(CAR, 3_000)).isEqualTo(1);
        assertThat(RideTokens.cost(CAR, 3_001)).isEqualTo(2);
        assertThat(RideTokens.cost(CAR, 10_000)).isEqualTo(2);
        assertThat(RideTokens.cost(CAR, 10_001)).isEqualTo(4);
    }

    @Test
    @DisplayName("the order rows arrive in doesn't decide the price")
    void orderIndependent() {
        List<RideTokens.Band> shuffled = List.of(
            new RideTokens.Band(2_000_000_000, 4),
            new RideTokens.Band(10_000, 2),
            new RideTokens.Band(3_000, 1));
        assertThat(RideTokens.cost(shuffled, 500)).isEqualTo(1);
        assertThat(RideTokens.cost(shuffled, 40_000)).isEqualTo(4);
    }

    @Test
    @DisplayName("nothing covers the distance: free, not the most expensive band")
    void uncoveredIsFree() {
        List<RideTokens.Band> noCatchAll = List.of(
            new RideTokens.Band(3_000, 1),
            new RideTokens.Band(10_000, 2));
        // A deleted catch-all is a bug somebody reports if trips go free, and one
        // they leave over if trips are silently overcharged.
        assertThat(RideTokens.cost(noCatchAll, 25_000)).isZero();
        assertThat(RideTokens.cost(List.of(), 1_000)).isZero();
    }

    @Test
    @DisplayName("a zero-token band is the off switch, not a missing price")
    void zeroIsAPrice() {
        assertThat(RideTokens.cost(List.of(new RideTokens.Band(2_000_000_000, 0)), 9_000))
            .isZero();
    }

    @Test
    @DisplayName("the cheapest ride is the smallest band, not the shortest one")
    void cheapestIsAMinimumNotAnAssumption() {
        // Nothing in the schema says a longer trip must cost more, so reading the
        // shortest band as the cheapest would be an assumption it does not make.
        List<RideTokens.Band> upsideDown = List.of(
            new RideTokens.Band(3_000, 5),
            new RideTokens.Band(2_000_000_000, 2));
        assertThat(RideTokens.cheapest(upsideDown)).isEqualTo(2);
        assertThat(RideTokens.cheapest(CAR)).isEqualTo(1);
        assertThat(RideTokens.cheapest(List.of())).isZero();
    }
}
