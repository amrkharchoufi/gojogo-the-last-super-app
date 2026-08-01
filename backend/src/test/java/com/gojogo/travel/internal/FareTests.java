package com.gojogo.travel.internal;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * What a trip costs.
 *
 * <p>Every number a rider sees comes out of this class, and nothing on the build
 * machine can execute SQL — so this is where a fare gets to be wrong for the
 * first time, rather than in production against somebody's wallet.
 */
class FareTests {

    private static final Fares.Pricing CAR = new Fares.Pricing(200, 120, 15, 500, 10_000);

    @Test
    @DisplayName("a road route is longer than a straight line, by about a third")
    void roadFactorInflatesTheStraightLine() {
        // Two points ~1.6 km apart in central Casablanca.
        Fares.Route route = Fares.estimate(33.5731, -7.5898, 33.5850, -7.5990, 13_000, 24);

        double straightMetres = Fares.distanceKm(33.5731, -7.5898, 33.5850, -7.5990) * 1000;
        assertThat(route.metres()).isGreaterThan((long) straightMetres);
        assertThat(route.metres()).isCloseTo((long) (straightMetres * 1.3),
            org.assertj.core.data.Offset.offset(2L));
    }

    @Test
    @DisplayName("duration follows distance at the assumed city speed")
    void durationFollowsSpeed() {
        Fares.Route slow = Fares.estimate(33.5731, -7.5898, 33.6, -7.62, 13_000, 12);
        Fares.Route fast = Fares.estimate(33.5731, -7.5898, 33.6, -7.62, 13_000, 48);

        assertThat(slow.metres()).isEqualTo(fast.metres());
        // Four times the speed, a quarter of the time.
        assertThat(slow.seconds()).isCloseTo(fast.seconds() * 4,
            org.assertj.core.data.Offset.offset(2L));
    }

    @Test
    @DisplayName("a speed of zero falls back rather than dividing by it")
    void zeroSpeedFallsBack() {
        Fares.Route route = Fares.estimate(33.5731, -7.5898, 33.6, -7.62, 13_000, 0);

        // A typo in a config row must not produce a trip that takes forever.
        assertThat(route.seconds()).isPositive();
        assertThat(route.seconds()).isLessThan(7200);
    }

    @Test
    @DisplayName("a fare is base plus distance plus time")
    void fareAddsUp() {
        // Exactly 10 km, 30 minutes.
        Fares.Route route = new Fares.Route(10_000, 1_800);

        // 200 + 10×120 + 30×15 = 1850.
        assertThat(Fares.suggest(route, CAR)).isEqualTo(1850);
    }

    @Test
    @DisplayName("a very short hop still costs the minimum")
    void minimumIsAFloor() {
        Fares.Route roundTheCorner = new Fares.Route(150, 40);

        // 200 + 0.15×120 + 0.67×15 ≈ 228, which the floor lifts to 500.
        assertThat(Fares.suggest(roundTheCorner, CAR)).isEqualTo(500);
    }

    @Test
    @DisplayName("surge multiplies the whole fare, and 100% is no surge")
    void surgeMultiplies() {
        Fares.Route route = new Fares.Route(10_000, 1_800);
        Fares.Pricing surged = new Fares.Pricing(200, 120, 15, 500, 15_000);

        assertThat(Fares.suggest(route, CAR)).isEqualTo(1850);
        assertThat(Fares.suggest(route, surged)).isEqualTo(2775);
    }

    @Test
    @DisplayName("rounding goes up, and only at the end")
    void roundingFavoursThePlatformAndHappensOnce() {
        // Fractions in every term, and long enough that the minimum doesn't
        // bind — otherwise the floor is what is being tested, not the rounding.
        Fares.Route route = new Fares.Route(7_234, 1_331);
        long fare = Fares.suggest(route, CAR);

        // Rounding each term would compound; rounding down would lose a
        // fraction of a cent on every single trip, forever.
        double exact = 200 + 7.234 * 120 + (1_331 / 60d) * 15;
        assertThat(fare).isEqualTo((long) Math.ceil(exact));
        assertThat(fare).isGreaterThan(CAR.minimumMinor());
    }

    @Test
    @DisplayName("an offer under the minimum is refused — 'make me an offer' needs a bottom")
    void offersHaveAFloor() {
        assertThat(Fares.isAcceptableOffer(499, 1850, CAR, 30_000)).isFalse();
        assertThat(Fares.isAcceptableOffer(500, 1850, CAR, 30_000)).isTrue();
    }

    @Test
    @DisplayName("an offer far above the suggestion is refused too — that ceiling "
        + "protects the rider, not the driver")
    void offersHaveACeiling() {
        // A fat-fingered 5000 where 500 was meant is a mistake the server should
        // catch, not a windfall. The ceiling itself is allowed — 3× the
        // suggestion of 1850 is 5550, and it is the first minor unit past it
        // that is refused.
        assertThat(Fares.isAcceptableOffer(5_550, 1_850, CAR, 30_000)).isTrue();
        assertThat(Fares.isAcceptableOffer(5_551, 1_850, CAR, 30_000)).isFalse();
        assertThat(Fares.isAcceptableOffer(7_000, 1_850, CAR, 40_000)).isTrue();
    }

    @Test
    @DisplayName("the ceiling never drops below the minimum, however cheap the trip")
    void ceilingNeverUndercutsTheFloor() {
        // A 200-minor suggestion with a 1× multiple would otherwise make the
        // floor unreachable and every offer invalid.
        assertThat(Fares.isAcceptableOffer(500, 200, CAR, 10_000)).isTrue();
    }

    @Test
    @DisplayName("distance is symmetric and zero for a point")
    void distanceSanity() {
        assertThat(Fares.distanceKm(33.5731, -7.5898, 33.5731, -7.5898)).isZero();
        assertThat(Fares.distanceKm(33.5731, -7.5898, 34.0209, -6.8416))
            .isEqualTo(Fares.distanceKm(34.0209, -6.8416, 33.5731, -7.5898));
    }
}
