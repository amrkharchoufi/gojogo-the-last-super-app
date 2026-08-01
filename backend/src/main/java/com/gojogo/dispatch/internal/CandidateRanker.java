package com.gojogo.dispatch.internal;

import com.gojogo.dispatch.VehicleCategory;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.Comparator;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * Who to ask, in what order — SPECS §3's candidate search, as a pure function.
 *
 * <p>Deliberately not SQL. The filters that matter (a stale position, a category
 * that doesn't fit, somebody already asked about this job) are cheap in Java over
 * a shortlist the database has already narrowed by kind, status and a latitude
 * window, and writing them as one large query would put the most consequential
 * logic in this module somewhere nothing on the build machine can execute.
 *
 * <p><b>Why three terms.</b> Proximity alone hands every job on a quiet afternoon
 * to whoever parked closest to the restaurant, and the driver two streets further
 * out earns nothing all day; rating alone does the same to the best-rated person
 * in the city. Idle time is the term that makes the queue a queue.
 */
final class CandidateRanker {

    private CandidateRanker() {
    }

    /**
     * One worker as the ranker sees them. A record rather than the entity so the
     * scoring can be exercised without a database — and so it is obvious that
     * nothing here can accidentally read another column.
     */
    record Candidate(UUID workerId, UUID userId, VehicleCategory category,
                     Double latitude, Double longitude, OffsetDateTime positionAt,
                     double rating, OffsetDateTime idleSince) {
    }

    /** A candidate that survived, with the distance already measured. */
    record Ranked(Candidate candidate, double distanceKm, double score) {
    }

    /**
     * The rules a candidate has to pass and the order the survivors come back in.
     *
     * @param exclude workers already offered this job in an earlier ring. A wave
     *                that re-asks the driver who just declined is the fastest way
     *                to teach them to turn the app off
     * @param limit   the wave size — the shortlist is truncated, not the search
     */
    static List<Ranked> rank(List<Candidate> candidates, Policy policy, double latitude,
                             double longitude, double radiusKm, Set<VehicleCategory> categories,
                             Set<UUID> exclude, int limit, OffsetDateTime now) {
        OffsetDateTime freshEnough = now.minusSeconds(policy.presenceStaleSeconds());
        return candidates.stream()
            .filter(c -> !exclude.contains(c.workerId()))
            .filter(c -> categories.contains(c.category()))
            // No position, or one old enough that drawing it on a map would be a
            // lie: a phone that stopped reporting is not a driver standing still.
            .filter(c -> c.latitude() != null && c.longitude() != null
                && c.positionAt() != null && !c.positionAt().isBefore(freshEnough))
            .filter(c -> c.rating() >= policy.ratingFloor())
            .map(c -> new Ranked(c,
                Geo.distanceKm(latitude, longitude, c.latitude(), c.longitude()), 0))
            // The box the database filtered on is a square; the ring is a circle.
            .filter(r -> r.distanceKm() <= radiusKm)
            .map(r -> new Ranked(r.candidate(), r.distanceKm(),
                score(r.candidate(), r.distanceKm(), radiusKm, policy, now)))
            .sorted(Comparator.comparingDouble(Ranked::score).reversed()
                // A stable tiebreak, so a rerun of the same wave offers the same
                // people rather than shuffling by whatever order the rows arrived.
                .thenComparingDouble(Ranked::distanceKm)
                .thenComparing(r -> r.candidate().workerId()))
            .limit(Math.max(0, limit))
            .toList();
    }

    /**
     * Zero to one, higher is better. Every term is normalised before it is
     * weighted, because a raw kilometre and a raw star are not comparable and
     * weights over incomparable units are weights nobody can reason about.
     */
    private static double score(Candidate candidate, double distanceKm, double radiusKm,
                                Policy policy, OffsetDateTime now) {
        double proximity = radiusKm <= 0 ? 1 : 1 - Math.min(1, distanceKm / radiusKm);
        double rating = Math.clamp(candidate.rating() / 5.0, 0, 1);
        long idleSeconds = candidate.idleSince() == null ? 0
            : Math.max(0, Duration.between(candidate.idleSince(), now).toSeconds());
        double idle = policy.idleFullSeconds() <= 0 ? 0
            : Math.min(1, (double) idleSeconds / policy.idleFullSeconds());
        double total = policy.proximityWeight() + policy.ratingWeight() + policy.idleWeight();
        if (total <= 0) return proximity;
        return (proximity * policy.proximityWeight()
            + rating * policy.ratingWeight()
            + idle * policy.idleWeight()) / total;
    }

    /**
     * The knobs, read from the config registry per call. A record rather than
     * fields on a bean so the ranker stays a function of its inputs, and so a
     * test can state the policy it is testing instead of arranging one.
     */
    record Policy(long presenceStaleSeconds, double ratingFloor, long idleFullSeconds,
                  double proximityWeight, double ratingWeight, double idleWeight) {
    }
}
