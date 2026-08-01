package com.gojogo.dispatch.internal;

import com.gojogo.dispatch.VehicleCategory;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.OffsetDateTime;
import java.util.EnumSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Who gets asked, and in what order.
 *
 * <p>The filters are where the damage is. Offering a job to somebody whose phone
 * stopped reporting twenty minutes ago wastes a whole ring on a driver who is at
 * home; re-offering it to the person who just declined teaches them to close the
 * app. Both are silent failures — nothing errors, the trip simply takes longer
 * to fill — so they are pinned here rather than discovered.
 */
class CandidateRankingTests {

    private static final double LAT = 33.5731;
    private static final double LON = -7.5898;
    private static final OffsetDateTime NOW = OffsetDateTime.parse("2026-08-01T12:00:00Z");
    private static final Set<VehicleCategory> CARS =
        EnumSet.of(VehicleCategory.CAR, VehicleCategory.COMFORT);

    /** Proximity only, so ordering tests read as pure distance unless they say otherwise. */
    private static final CandidateRanker.Policy PROXIMITY_ONLY =
        new CandidateRanker.Policy(60, 0, 900, 1, 0, 0);
    private static final CandidateRanker.Policy DEFAULTS =
        new CandidateRanker.Policy(60, 0, 900, 60, 25, 15);

    @Test
    @DisplayName("closest first")
    void nearestWins() {
        CandidateRanker.Candidate near = candidate(LAT + 0.002, LON, 5.0, NOW);
        CandidateRanker.Candidate far = candidate(LAT + 0.008, LON, 5.0, NOW);

        List<CandidateRanker.Ranked> ranked = rank(List.of(far, near), PROXIMITY_ONLY, 3, 5);

        assertThat(ranked).hasSize(2);
        assertThat(ranked.get(0).candidate()).isEqualTo(near);
        assertThat(ranked.get(0).distanceKm()).isLessThan(ranked.get(1).distanceKm());
    }

    @Test
    @DisplayName("the ring is a circle, not the square the database filtered on")
    void outsideTheRadiusIsExcluded() {
        // ~2.2 km away: inside the box a 2 km search hands to Postgres, outside
        // the ring itself.
        CandidateRanker.Candidate corner = candidate(LAT + 0.014, LON + 0.017, 5.0, NOW);

        assertThat(rank(List.of(corner), PROXIMITY_ONLY, 2, 5)).isEmpty();
        assertThat(rank(List.of(corner), PROXIMITY_ONLY, 3, 5)).hasSize(1);
    }

    @Test
    @DisplayName("a position nobody has updated is not a location")
    void staleReportsAreSkipped() {
        CandidateRanker.Candidate stale = candidate(LAT, LON, 5.0, NOW.minusSeconds(61));
        CandidateRanker.Candidate fresh = candidate(LAT + 0.01, LON, 5.0, NOW.minusSeconds(59));

        List<CandidateRanker.Ranked> ranked = rank(List.of(stale, fresh), PROXIMITY_ONLY, 3, 5);

        // The stale one is nearer and still loses — a phone that went quiet is
        // not a driver standing still.
        assertThat(ranked).extracting(r -> r.candidate().workerId())
            .containsExactly(fresh.workerId());
    }

    @Test
    @DisplayName("a worker who has never reported a position is not a candidate")
    void positionlessWorkersAreSkipped() {
        CandidateRanker.Candidate never = new CandidateRanker.Candidate(UUID.randomUUID(),
            UUID.randomUUID(), VehicleCategory.CAR, null, null, null, 5.0, NOW);

        assertThat(rank(List.of(never), PROXIMITY_ONLY, 7, 5)).isEmpty();
    }

    @Test
    @DisplayName("the wrong vehicle is not offered the job")
    void categoryFilters() {
        CandidateRanker.Candidate bike = new CandidateRanker.Candidate(UUID.randomUUID(),
            UUID.randomUUID(), VehicleCategory.BIKE, LAT, LON, NOW, 5.0, NOW);
        CandidateRanker.Candidate car = candidate(LAT + 0.01, LON, 5.0, NOW);

        assertThat(rank(List.of(bike, car), PROXIMITY_ONLY, 7, 5))
            .extracting(r -> r.candidate().workerId())
            .containsExactly(car.workerId());
    }

    @Test
    @DisplayName("nobody is asked about the same job twice, however many rings run")
    void alreadyOfferedAreExcluded() {
        CandidateRanker.Candidate asked = candidate(LAT, LON, 5.0, NOW);
        CandidateRanker.Candidate fresh = candidate(LAT + 0.01, LON, 5.0, NOW);

        List<CandidateRanker.Ranked> ranked = CandidateRanker.rank(List.of(asked, fresh),
            PROXIMITY_ONLY, LAT, LON, 7, CARS, Set.of(asked.workerId()), 5, NOW);

        assertThat(ranked).extracting(r -> r.candidate().workerId())
            .containsExactly(fresh.workerId());
    }

    @Test
    @DisplayName("a rating floor of zero — the launch default — excludes nobody")
    void ratingFloorOffByDefault() {
        CandidateRanker.Candidate poorlyRated = candidate(LAT, LON, 1.0, NOW);

        assertThat(rank(List.of(poorlyRated), DEFAULTS, 7, 5)).hasSize(1);
    }

    @Test
    @DisplayName("a rating floor, once set, is applied at the boundary and not below it")
    void ratingFloorApplies() {
        CandidateRanker.Policy floored = new CandidateRanker.Policy(60, 4.0, 900, 1, 0, 0);
        CandidateRanker.Candidate exactly = candidate(LAT, LON, 4.0, NOW);
        CandidateRanker.Candidate under = candidate(LAT, LON, 3.99, NOW);

        assertThat(rank(List.of(exactly, under), floored, 7, 5))
            .extracting(r -> r.candidate().workerId())
            .containsExactly(exactly.workerId());
    }

    @Test
    @DisplayName("between two drivers about as close as each other, an hour of "
        + "waiting wins — otherwise the nearest one takes every job all afternoon")
    void idleTimeBreaksStarvation() {
        CandidateRanker.Candidate justFinished = candidate(LAT + 0.005, LON, 5.0, NOW, NOW);
        CandidateRanker.Candidate waitingAges =
            candidate(LAT + 0.008, LON, 5.0, NOW, NOW.minusSeconds(3600));

        List<CandidateRanker.Ranked> withIdle =
            rank(List.of(justFinished, waitingAges), DEFAULTS, 3, 5);
        List<CandidateRanker.Ranked> withoutIdle =
            rank(List.of(justFinished, waitingAges), PROXIMITY_ONLY, 3, 5);

        assertThat(withIdle.get(0).candidate()).isEqualTo(waitingAges);
        // The same two people, ranked the other way round without the term —
        // which is what proves the term is doing the work.
        assertThat(withoutIdle.get(0).candidate()).isEqualTo(justFinished);
    }

    @Test
    @DisplayName("but it does not send a rider a driver two kilometres further away "
        + "just because that driver has been waiting")
    void proximityStillWinsAcrossARealGap() {
        CandidateRanker.Candidate close = candidate(LAT + 0.001, LON, 5.0, NOW, NOW);
        CandidateRanker.Candidate farButIdle =
            candidate(LAT + 0.02, LON, 5.0, NOW, NOW.minusSeconds(86400));

        // The weights encode a trade-off, not a queue: fairness between drivers
        // is a tiebreak, and the passenger standing in the street outranks it.
        assertThat(rank(List.of(close, farButIdle), DEFAULTS, 3, 5).get(0).candidate())
            .isEqualTo(close);
    }

    @Test
    @DisplayName("waiting longer than the full-credit window adds nothing more")
    void idleCreditSaturates() {
        CandidateRanker.Candidate anHour =
            candidate(LAT + 0.02, LON, 5.0, NOW, NOW.minusSeconds(3600));
        CandidateRanker.Candidate allDay =
            candidate(LAT + 0.02, LON, 5.0, NOW, NOW.minusSeconds(86400));

        List<CandidateRanker.Ranked> ranked = rank(List.of(anHour, allDay), DEFAULTS, 7, 5);

        assertThat(ranked.get(0).score()).isEqualTo(ranked.get(1).score());
    }

    @Test
    @DisplayName("the wave is a shortlist: only as many as the wave size, best first")
    void waveSizeTruncates() {
        List<CandidateRanker.Candidate> eight = List.of(
            candidate(LAT + 0.001, LON, 5.0, NOW), candidate(LAT + 0.002, LON, 5.0, NOW),
            candidate(LAT + 0.003, LON, 5.0, NOW), candidate(LAT + 0.004, LON, 5.0, NOW),
            candidate(LAT + 0.005, LON, 5.0, NOW), candidate(LAT + 0.006, LON, 5.0, NOW),
            candidate(LAT + 0.007, LON, 5.0, NOW), candidate(LAT + 0.008, LON, 5.0, NOW));

        List<CandidateRanker.Ranked> ranked = rank(eight, PROXIMITY_ONLY, 7, 3);

        assertThat(ranked).hasSize(3);
        assertThat(ranked).extracting(r -> r.candidate().workerId())
            .containsExactly(eight.get(0).workerId(), eight.get(1).workerId(),
                eight.get(2).workerId());
    }

    @Test
    @DisplayName("the same wave run twice offers the same people, in the same order")
    void rankingIsStable() {
        // Two candidates identical in every ranked input: without the tiebreak
        // the order would be whatever the database happened to return, and a
        // retried wave would offer a different person for no reason.
        CandidateRanker.Candidate a = candidate(LAT + 0.005, LON, 5.0, NOW);
        CandidateRanker.Candidate b = candidate(LAT + 0.005, LON, 5.0, NOW);

        assertThat(rank(List.of(a, b), DEFAULTS, 7, 5))
            .extracting(r -> r.candidate().workerId())
            .isEqualTo(rank(List.of(b, a), DEFAULTS, 7, 5).stream()
                .map(r -> r.candidate().workerId()).toList());
    }

    @Test
    @DisplayName("an empty ring is empty, not an error")
    void nobodyThere() {
        assertThat(rank(List.of(), DEFAULTS, 7, 5)).isEmpty();
    }

    private static List<CandidateRanker.Ranked> rank(List<CandidateRanker.Candidate> candidates,
                                                     CandidateRanker.Policy policy,
                                                     double radiusKm, int limit) {
        return CandidateRanker.rank(candidates, policy, LAT, LON, radiusKm, CARS,
            Set.of(), limit, NOW);
    }

    private static CandidateRanker.Candidate candidate(double lat, double lon, double rating,
                                                       OffsetDateTime positionAt) {
        return candidate(lat, lon, rating, positionAt, NOW);
    }

    private static CandidateRanker.Candidate candidate(double lat, double lon, double rating,
                                                       OffsetDateTime positionAt,
                                                       OffsetDateTime idleSince) {
        return new CandidateRanker.Candidate(UUID.randomUUID(), UUID.randomUUID(),
            VehicleCategory.CAR, lat, lon, positionAt, rating, idleSince);
    }
}
