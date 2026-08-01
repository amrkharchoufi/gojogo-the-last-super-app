package com.gojogo.travel.internal;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

interface RideRepository extends JpaRepository<Ride, UUID> {

    /**
     * The rider's one live ride, if they have one. Deliberately singular: a
     * person cannot be in two cars, and letting them request a second while one
     * is running is how you get two drivers at one address.
     */
    @Query("select r from Ride r where r.riderId = :riderId and r.state in :states "
        + "order by r.requestedAt desc")
    List<Ride> liveForRider(@Param("riderId") UUID riderId,
                            @Param("states") Collection<RideState> states, Pageable page);

    @Query("select r from Ride r where r.driverUserId = :driverUserId and r.state in :states "
        + "order by r.requestedAt desc")
    List<Ride> liveForDriver(@Param("driverUserId") UUID driverUserId,
                             @Param("states") Collection<RideState> states, Pageable page);

    List<Ride> findByRiderIdOrderByRequestedAtDesc(UUID riderId, Pageable page);

    List<Ride> findByDriverUserIdOrderByRequestedAtDesc(UUID driverUserId, Pageable page);

    /** The expiry sweep: searches that ran out of time. */
    @Query("select r from Ride r where r.state in :states and r.expiresAt <= :now "
        + "order by r.expiresAt asc")
    List<Ride> expired(@Param("states") Collection<RideState> states,
                       @Param("now") OffsetDateTime now, Pageable page);
}

interface RideOfferRepository extends JpaRepository<RideOffer, UUID> {

    List<RideOffer> findByRideIdOrderByCreatedAtAsc(UUID rideId);

    List<RideOffer> findByRideIdAndState(UUID rideId, RideOfferState state);

    List<RideOffer> findByRideIdAndDriverWorkerIdOrderByCreatedAtAsc(UUID rideId,
                                                                     UUID driverWorkerId);

    /** What is on one driver's screen: their live counters across every ride. */
    List<RideOffer> findByDriverUserIdAndStateOrderByCreatedAtAsc(UUID driverUserId,
                                                                  RideOfferState state);

    List<RideOffer> findByStateAndExpiresAtBefore(RideOfferState state, OffsetDateTime cutoff,
                                                  Pageable page);
}

interface RideTokenPriceRepository extends JpaRepository<RideTokenPrice, UUID> {

    /**
     * Every band in force for a category, newest effective generation first.
     *
     * <p>Returns the whole history that has taken effect rather than one row,
     * because a "band" is a set: the caller keeps only the rows sharing the
     * newest {@code effectiveFrom}, which is what makes scheduling a price
     * change an insert of several rows with one timestamp.
     */
    @Query("select p from RideTokenPrice p where p.category = :category "
        + "and p.effectiveFrom <= :now order by p.effectiveFrom desc, p.upToMetres asc")
    List<RideTokenPrice> inForce(@Param("category") String category,
                                 @Param("now") OffsetDateTime now);
}

interface PricingConfigRepository extends JpaRepository<PricingConfig, UUID> {

    /**
     * The list in force for a category. Newest effective row first and take one —
     * effective-dating with a future row is how a price change is scheduled, and
     * this is the query that must not pick it up early.
     */
    @Query("select p from PricingConfig p where p.category = :category "
        + "and p.effectiveFrom <= :now order by p.effectiveFrom desc")
    List<PricingConfig> inForce(@Param("category") String category,
                                @Param("now") OffsetDateTime now, Pageable page);
}
