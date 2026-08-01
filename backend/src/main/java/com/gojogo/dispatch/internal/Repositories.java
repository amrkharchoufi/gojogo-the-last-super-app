package com.gojogo.dispatch.internal;

import com.gojogo.dispatch.JobKind;
import com.gojogo.dispatch.WorkerKind;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

interface WorkerRepository extends JpaRepository<Worker, UUID> {

    Optional<Worker> findByUserIdAndKind(UUID userId, WorkerKind kind);

    List<Worker> findByUserIdOrderByKindAsc(UUID userId);

    /**
     * The candidate shortlist: the right registry, signed on, not blocked, and
     * inside a latitude/longitude window that certainly contains the ring.
     *
     * <p>Deliberately a box and not a circle. Postgres has no idea what a great
     * circle is without PostGIS, the window is a plain index-friendly comparison,
     * and {@link CandidateRanker} measures the real distance over what comes
     * back. Generous by design — a box that excluded somebody two hundred metres
     * away would lose them silently.
     */
    @Query("select w from Worker w where w.kind = :kind and w.status = :status "
        + "and w.suspended = false "
        + "and w.latitude between :minLat and :maxLat "
        + "and w.longitude between :minLon and :maxLon")
    List<Worker> inBox(@Param("kind") WorkerKind kind, @Param("status") WorkerStatus status,
                       @Param("minLat") double minLatitude, @Param("maxLat") double maxLatitude,
                       @Param("minLon") double minLongitude, @Param("maxLon") double maxLongitude,
                       Pageable page);
}

interface DispatchJobRepository extends JpaRepository<DispatchJob, UUID> {

    Optional<DispatchJob> findByJobKindAndJobRefId(JobKind jobKind, UUID jobRefId);

    /** Searches whose next ring is due. */
    @Query("select j from DispatchJob j where j.state = :state and j.nextWaveAt <= :now "
        + "order by j.nextWaveAt asc")
    List<DispatchJob> dueForWave(@Param("state") JobState state,
                                 @Param("now") OffsetDateTime now, Pageable page);

    /**
     * Searches that have run out of time. A second query rather than an
     * {@code or} in the one above: nothing on the build machine can execute
     * JPQL, and a two-branch predicate is exactly the shape that first fails in
     * production.
     */
    @Query("select j from DispatchJob j where j.state = :state and j.expiresAt <= :now "
        + "order by j.expiresAt asc")
    List<DispatchJob> expired(@Param("state") JobState state,
                              @Param("now") OffsetDateTime now, Pageable page);
}

interface OfferRepository extends JpaRepository<Offer, UUID> {

    Optional<Offer> findByJobIdAndWorkerId(UUID jobId, UUID workerId);

    List<Offer> findByJobId(UUID jobId);

    List<Offer> findByJobIdAndState(UUID jobId, OfferState state);

    List<Offer> findByWorkerIdAndStateOrderByOfferedAtAsc(UUID workerId, OfferState state);

    /** The expiry sweep: offers nobody answered in time. */
    List<Offer> findByStateAndExpiresAtBefore(OfferState state, OffsetDateTime cutoff,
                                              Pageable page);

    /** Rolling-window performance counters (SPECS §3). One count per state,
     *  because a grouped projection is a query this build cannot try out. */
    long countByWorkerIdAndOfferedAtAfter(UUID workerId, OffsetDateTime since);

    long countByWorkerIdAndStateAndOfferedAtAfter(UUID workerId, OfferState state,
                                                  OffsetDateTime since);
}
