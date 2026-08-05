package com.gojogo.services.internal;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

interface ProviderRepository extends JpaRepository<Provider, UUID> {

    Optional<Provider> findByOwnerUserId(UUID ownerUserId);
}

interface ProviderDocumentRepository extends JpaRepository<ProviderDocument, UUID> {

    List<ProviderDocument> findByProviderIdOrderByUploadedAtAsc(UUID providerId);
}

interface ServiceOfferingRepository extends JpaRepository<ServiceOffering, UUID> {

    @Query("""
        select s from ServiceOffering s
        where s.active = true and s.hiddenAt is null
          and s.createdAt < :before
          and (:category is null or s.category = :category)
          and (:providerId is null or s.providerId = :providerId)
          and not exists (select p from Provider p where p.id = s.providerId and p.suspended = true)
        order by s.createdAt desc
        """)
    List<ServiceOffering> browse(@Param("category") String category,
                                 @Param("providerId") UUID providerId,
                                 @Param("before") OffsetDateTime before, Pageable page);

    List<ServiceOffering> findByProviderIdOrderByCreatedAtDesc(UUID providerId, Pageable page);
}

interface AvailabilityRuleRepository extends JpaRepository<AvailabilityRule, UUID> {

    List<AvailabilityRule> findByProviderIdOrderByDayOfWeekAscStartMinuteAsc(UUID providerId);

    void deleteByProviderId(UUID providerId);
}

interface AvailabilityExceptionRepository extends JpaRepository<AvailabilityException, UUID> {

    List<AvailabilityException> findByProviderIdAndOnDateBetween(
        UUID providerId, LocalDate from, LocalDate to);

    List<AvailabilityException> findByProviderIdOrderByOnDateAsc(UUID providerId);

    void deleteByProviderIdAndOnDate(UUID providerId, LocalDate onDate);
}

interface BookingRepository extends JpaRepository<Booking, UUID> {

    /** Everything still holding a slot in the window — what availability
     *  subtracts and what a new request must not overlap. */
    @Query("""
        select b from Booking b
        where b.providerId = :providerId
          and b.status in (com.gojogo.services.internal.BookingStatus.REQUESTED,
                           com.gojogo.services.internal.BookingStatus.CONFIRMED)
          and b.startsAt < :to
          and b.startsAt > :fromLessLongest
        """)
    List<Booking> liveInWindow(@Param("providerId") UUID providerId,
                               @Param("fromLessLongest") OffsetDateTime fromLessLongest,
                               @Param("to") OffsetDateTime to);

    List<Booking> findByCustomerIdOrderByRequestedAtDesc(UUID customerId, Pageable page);

    List<Booking> findByProviderIdOrderByStartsAtDesc(UUID providerId, Pageable page);

    List<Booking> findByProviderIdAndStatusOrderByStartsAtAsc(
        UUID providerId, BookingStatus status, Pageable page);

    /** Requests nobody answered inside the confirm window. */
    List<Booking> findByStatusAndRequestedAtBefore(
        BookingStatus status, OffsetDateTime cutoff, Pageable page);

    /** Completed work whose capture window has passed and whose money hasn't moved. */
    @Query("""
        select b from Booking b
        where b.status = com.gojogo.services.internal.BookingStatus.COMPLETED
          and b.paymentStatus = com.gojogo.services.internal.BookingPaymentState.HELD
          and b.completedAt < :cutoff
        """)
    List<Booking> settleable(@Param("cutoff") OffsetDateTime cutoff, Pageable page);

    /** Confirmed appointments inside the reminder window that haven't had this
     *  reminder yet. */
    @Query("""
        select b from Booking b
        where b.status = com.gojogo.services.internal.BookingStatus.CONFIRMED
          and b.startsAt between :from and :to
          and ((:hoursAhead = 24 and b.reminded24h = false)
            or (:hoursAhead = 1 and b.reminded1h = false))
        """)
    List<Booking> remindable(@Param("from") OffsetDateTime from, @Param("to") OffsetDateTime to,
                             @Param("hoursAhead") int hoursAhead, Pageable page);
}

interface ServiceReviewRepository extends JpaRepository<ServiceReview, UUID> {

    Optional<ServiceReview> findByServiceIdAndAuthorId(UUID serviceId, UUID authorId);

    List<ServiceReview> findByServiceIdOrderByCreatedAtDesc(UUID serviceId, Pageable page);
}
