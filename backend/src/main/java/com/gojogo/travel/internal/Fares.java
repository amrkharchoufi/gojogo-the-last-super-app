package com.gojogo.travel.internal;

/**
 * What a ride costs, and how far it is — the two pieces of arithmetic this
 * module is built on, kept apart from everything that touches a database so they
 * can actually be tested. Nothing on the build machine can execute SQL, and a
 * fare is the last number in this system that should first be computed in
 * production.
 */
final class Fares {

    private static final double EARTH_RADIUS_KM = 6371.0088;

    private Fares() {
    }

    /**
     * A route, estimated.
     *
     * <p><b>Straight-line distance inflated by a road factor</b>, and a duration
     * from an assumed city speed. SPECS §3 specifies Mapbox Directions as the
     * authority and it should be — but the server has no Mapbox token (the app's
     * is a client token for map tiles), wiring one is an account decision rather
     * than a code change, and a routing call per quote is a per-request cost
     * somebody should choose deliberately.
     *
     * <p>So the seam is here and the estimate is honest about being one: a
     * 1.3× urban detour factor is within about 10% of real road distance in a
     * gridded city, and it is a <em>suggestion</em> the two parties then
     * negotiate away from anyway. Replacing this with a routing provider changes
     * this method and no caller.
     */
    static Route estimate(double fromLat, double fromLon, double toLat, double toLon,
                          long roadFactorBps, long speedKmh) {
        double straightKm = distanceKm(fromLat, fromLon, toLat, toLon);
        double roadKm = straightKm * Math.max(1, roadFactorBps) / 10_000d;
        long metres = Math.round(roadKm * 1000);
        // Guard the divide rather than the config: a speed of zero is a typo
        // somebody made, and a quote that takes forever is worse than one that
        // falls back.
        double kmh = speedKmh <= 0 ? 24 : speedKmh;
        long seconds = Math.round(roadKm / kmh * 3600);
        return new Route(metres, seconds);
    }

    /** Great-circle distance in kilometres. */
    static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
            + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
            * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        return 2 * EARTH_RADIUS_KM * Math.atan2(Math.sqrt(a), Math.sqrt(Math.max(0, 1 - a)));
    }

    /**
     * The suggested fare: base + distance + time, surged, floored at the
     * minimum.
     *
     * <p>Rounded <b>up</b> to whole minor units at the end and only at the end.
     * Rounding each term would compound, and rounding down would mean a platform
     * that loses a fraction of a cent on every trip — which is a rounding rule,
     * not an accident, and the kind that should be written down.
     */
    static long suggest(Route route, Pricing pricing) {
        double km = route.metres() / 1000d;
        double minutes = route.seconds() / 60d;
        double fare = pricing.baseMinor()
            + km * pricing.perKmMinor()
            + minutes * pricing.perMinuteMinor();
        fare = fare * Math.max(0, pricing.surgeBps()) / 10_000d;
        return Math.max(pricing.minimumMinor(), (long) Math.ceil(fare));
    }

    /**
     * Whether an amount is one somebody may put on the table.
     *
     * <p>The floor is the price list's minimum — without it, "make me an offer"
     * is an invitation to offer a penny. The ceiling is a sanity multiple of the
     * suggestion, and it protects the <em>rider</em>: a fat-fingered 5000 where
     * 50 was meant is a mistake the server should catch, not a windfall.
     */
    static boolean isAcceptableOffer(long amountMinor, long suggestedMinor, Pricing pricing,
                                     long maxMultipleBps) {
        if (amountMinor < pricing.minimumMinor()) return false;
        long ceiling = Math.max(pricing.minimumMinor(),
            Math.round(suggestedMinor * Math.max(10_000, maxMultipleBps) / 10_000d));
        return amountMinor <= ceiling;
    }

    /** Distance and duration, as estimated. */
    record Route(long metres, long seconds) {
    }

    /** The price list in force, flattened so the calculator takes no entity. */
    record Pricing(long baseMinor, long perKmMinor, long perMinuteMinor,
                   long minimumMinor, long surgeBps) {
    }
}
