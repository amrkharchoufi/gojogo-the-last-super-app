package com.gojogo.dispatch.internal;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The geometry, pinned.
 *
 * <p>This is the one class in the module whose bugs would be invisible: a
 * bounding box that is slightly too small silently loses the nearest driver, and
 * nothing anywhere logs "somebody was two hundred metres away and we didn't ask
 * them". So the interesting test is not "is the distance right" but <b>is the box
 * always at least as big as the circle</b>, checked all the way round rather than
 * at the four points a careless test would pick.
 */
class GeoTests {

    private static final double CASABLANCA_LAT = 33.5731;
    private static final double CASABLANCA_LON = -7.5898;

    @Test
    @DisplayName("a point is no distance from itself")
    void zeroDistance() {
        assertThat(Geo.distanceKm(CASABLANCA_LAT, CASABLANCA_LON,
            CASABLANCA_LAT, CASABLANCA_LON)).isZero();
    }

    @Test
    @DisplayName("a degree of latitude is about 111 km, anywhere")
    void degreeOfLatitude() {
        assertThat(Geo.distanceKm(0, 0, 1, 0)).isCloseTo(111.19, within(0.1));
        assertThat(Geo.distanceKm(60, 25, 61, 25)).isCloseTo(111.19, within(0.1));
    }

    @Test
    @DisplayName("a degree of longitude shrinks towards the poles — the error flat "
        + "geometry would make")
    void degreeOfLongitude() {
        assertThat(Geo.distanceKm(0, 0, 0, 1)).isCloseTo(111.19, within(0.1));
        // cos(60°) = 0.5, so half as far for the same degree.
        assertThat(Geo.distanceKm(60, 0, 60, 1)).isCloseTo(55.6, within(0.2));
    }

    @Test
    @DisplayName("Casablanca to Rabat is about 85 km, and the same both ways")
    void knownDistance() {
        double there = Geo.distanceKm(CASABLANCA_LAT, CASABLANCA_LON, 34.0209, -6.8416);
        double back = Geo.distanceKm(34.0209, -6.8416, CASABLANCA_LAT, CASABLANCA_LON);
        assertThat(there).isBetween(80.0, 90.0);
        assertThat(back).isEqualTo(there);
    }

    @Test
    @DisplayName("the box contains every point on the ring, in every direction")
    void boxCoversTheWholeRing() {
        for (double radiusKm : new double[] {0.5, 1, 3, 7, 25}) {
            Geo.Box box = Geo.box(CASABLANCA_LAT, CASABLANCA_LON, radiusKm);
            for (int bearing = 0; bearing < 360; bearing += 5) {
                double[] edge = destination(CASABLANCA_LAT, CASABLANCA_LON, radiusKm, bearing);
                assertThat(edge[0])
                    .as("latitude at %d° on a %.1f km ring", bearing, radiusKm)
                    .isBetween(box.minLatitude(), box.maxLatitude());
                assertThat(edge[1])
                    .as("longitude at %d° on a %.1f km ring", bearing, radiusKm)
                    .isBetween(box.minLongitude(), box.maxLongitude());
            }
        }
    }

    @Test
    @DisplayName("the box is a prefilter, not the answer: its corners are outside the ring")
    void boxIsGenerous() {
        Geo.Box box = Geo.box(CASABLANCA_LAT, CASABLANCA_LON, 3);
        double corner = Geo.distanceKm(CASABLANCA_LAT, CASABLANCA_LON,
            box.maxLatitude(), box.maxLongitude());
        // Which is exactly why CandidateRanker measures again over what comes back.
        assertThat(corner).isGreaterThan(3);
    }

    @Test
    @DisplayName("near a pole the longitude window opens all the way, rather than "
        + "producing a window that is too narrow")
    void polarBoxWidensToEverything() {
        Geo.Box box = Geo.box(89.99, 12, 5);
        assertThat(box.minLongitude()).isEqualTo(-180);
        assertThat(box.maxLongitude()).isEqualTo(180);
    }

    @Test
    @DisplayName("a window that would cross the antimeridian opens all the way too")
    void antimeridianWidensToEverything() {
        Geo.Box box = Geo.box(-16.9, 179.98, 7);
        assertThat(box.minLongitude()).isEqualTo(-180);
        assertThat(box.maxLongitude()).isEqualTo(180);
        // The latitude half still narrows — the whole world in one axis only.
        assertThat(box.maxLatitude() - box.minLatitude()).isLessThan(1);
    }

    @Test
    @DisplayName("latitude is clamped rather than wrapped past the pole")
    void latitudeClamps() {
        Geo.Box box = Geo.box(89.9, 0, 500);
        assertThat(box.maxLatitude()).isLessThanOrEqualTo(90);
        assertThat(box.minLatitude()).isGreaterThanOrEqualTo(-90);
    }

    /** Standard spherical destination point, so the ring test measures the real
     *  circle rather than the same approximation the box is built from. */
    private static double[] destination(double lat, double lon, double distanceKm,
                                        double bearingDegrees) {
        double angular = distanceKm / 6371.0088;
        double bearing = Math.toRadians(bearingDegrees);
        double lat1 = Math.toRadians(lat);
        double lon1 = Math.toRadians(lon);
        double lat2 = Math.asin(Math.sin(lat1) * Math.cos(angular)
            + Math.cos(lat1) * Math.sin(angular) * Math.cos(bearing));
        double lon2 = lon1 + Math.atan2(Math.sin(bearing) * Math.sin(angular) * Math.cos(lat1),
            Math.cos(angular) - Math.sin(lat1) * Math.sin(lat2));
        return new double[] {Math.toDegrees(lat2), Math.toDegrees(lon2)};
    }

    private static org.assertj.core.data.Offset<Double> within(double tolerance) {
        return org.assertj.core.data.Offset.offset(tolerance);
    }
}
