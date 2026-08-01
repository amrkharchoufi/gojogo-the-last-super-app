package com.gojogo.dispatch.internal;

/**
 * The two pieces of geometry this module needs, kept apart from everything that
 * touches a database so they can actually be tested — nothing on the build
 * machine can execute SQL, and "is this driver within a kilometre" is precisely
 * the kind of arithmetic that must not first run in production.
 *
 * <p>Flat, plane-geometry distance would be within a metre or two at these
 * scales, and it is still not used: it is wrong by a factor of {@code cos(lat)}
 * in longitude, which is invisible in a test written at the equator and a 25%
 * error in Oslo.
 */
final class Geo {

    /** Mean Earth radius. The ellipsoid's flattening is far below the error in a
     *  phone's own GPS fix, so a sphere is the honest model here. */
    private static final double EARTH_RADIUS_KM = 6371.0088;

    /**
     * A tenth of a percent of slack on the window.
     *
     * <p>Not superstition: the box is derived from {@code r/R} in radians and the
     * true edge of the circle comes out of {@code asin}, and the two disagree in
     * the last bit or so — enough for a point exactly on the ring to land a
     * fraction of a micrometre outside a box computed to be exact (a real test
     * failure, not a hypothetical). The prefilter is allowed to be generous and
     * must never be tight, so it is widened rather than balanced on an ulp. At
     * 7 km this is seven metres of extra scan.
     */
    private static final double PADDING = 1.001;

    private Geo() {
    }

    /** Great-circle distance in kilometres. */
    static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
            + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
            * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        // atan2 rather than asin: asin loses precision for antipodal points, and
        // clamping `a` at 1 is only half of that fix.
        return 2 * EARTH_RADIUS_KM * Math.atan2(Math.sqrt(a), Math.sqrt(Math.max(0, 1 - a)));
    }

    /**
     * A latitude/longitude window that certainly contains every point within
     * {@code radiusKm}, and some that aren't — the cheap prefilter the database
     * runs before Java measures what actually came back.
     *
     * <p>It is allowed to be generous and must never be tight: a box that
     * excluded a driver two hundred metres away would lose them silently, which
     * is a bug nobody would ever see reported.
     *
     * <p>Two cases collapse to "the whole world" rather than being modelled: a
     * window that crosses the antimeridian, and one near enough a pole that the
     * longitude span exceeds a hemisphere. Both would need a split range and
     * neither will ever be hit by a city, so the answer is a wider scan and a
     * correct result instead of a clever query.
     */
    static Box box(double latitude, double longitude, double radiusKm) {
        double latDelta = Math.toDegrees(radiusKm / EARTH_RADIUS_KM) * PADDING;
        double minLat = latitude - latDelta;
        double maxLat = latitude + latDelta;
        if (minLat <= -90 || maxLat >= 90) {
            return new Box(Math.max(-90, minLat), Math.min(90, maxLat), -180, 180);
        }
        // Longitude degrees shrink towards the poles; use the widest latitude in
        // the window, which is the one furthest from the equator.
        double widest = Math.max(Math.abs(minLat), Math.abs(maxLat));
        double cos = Math.cos(Math.toRadians(widest));
        if (cos < 1e-9) return new Box(minLat, maxLat, -180, 180);
        double lonDelta = latDelta / cos;
        if (lonDelta >= 180) return new Box(minLat, maxLat, -180, 180);
        double minLon = longitude - lonDelta;
        double maxLon = longitude + lonDelta;
        if (minLon < -180 || maxLon > 180) return new Box(minLat, maxLat, -180, 180);
        return new Box(minLat, maxLat, minLon, maxLon);
    }

    record Box(double minLatitude, double maxLatitude, double minLongitude, double maxLongitude) {
    }
}
