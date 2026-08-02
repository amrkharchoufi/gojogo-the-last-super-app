package com.gojogo.partner.internal;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

interface PartnerAccountRepository extends JpaRepository<PartnerAccount, UUID> {

    Optional<PartnerAccount> findByUserIdAndKind(UUID userId, PartnerKind kind);

    List<PartnerAccount> findByUserIdOrderByCreatedAtAsc(UUID userId);

    /** The reviewer's queue: one status at a time, oldest submission first. */
    List<PartnerAccount> findByStatusInOrderBySubmittedAtAscCreatedAtAsc(
        Collection<PartnerStatus> statuses, Pageable page);
}

interface PartnerDocumentRepository extends JpaRepository<PartnerDocument, UUID> {

    List<PartnerDocument> findByAccountIdOrderByKindAsc(UUID accountId);

    Optional<PartnerDocument> findByAccountIdAndKind(UUID accountId, DocumentKind kind);

    List<PartnerDocument> findByAccountIdInOrderByKindAsc(Collection<UUID> accountIds);
}

interface VehicleRepository extends JpaRepository<Vehicle, UUID> {

    List<Vehicle> findByAccountIdOrderByCreatedAtAsc(UUID accountId);

    List<Vehicle> findByAccountIdInOrderByCreatedAtAsc(Collection<UUID> accountIds);

    Optional<Vehicle> findByAccountIdAndActiveTrue(UUID accountId);

    /**
     * The expiry sweep: roadworthy vehicles whose papers ran out before a
     * cutoff. Two states rather than a helper predicate, because a JPQL
     * {@code in} over a bound collection is the one form this build can be sure
     * of without a database to try it against.
     */
    @Query("select v from Vehicle v where v.state in :states "
        + "and (v.registrationExpiresOn < :cutoff or v.insuranceExpiresOn < :cutoff) "
        + "order by v.updatedAt asc")
    List<Vehicle> lapsed(@Param("states") Collection<VehicleState> states,
                         @Param("cutoff") LocalDate cutoff, Pageable page);
}

interface VehicleDocumentRepository extends JpaRepository<VehicleDocument, UUID> {

    List<VehicleDocument> findByVehicleIdOrderByKindAsc(UUID vehicleId);

    List<VehicleDocument> findByVehicleIdInOrderByKindAsc(Collection<UUID> vehicleIds);

    Optional<VehicleDocument> findByVehicleIdAndKind(UUID vehicleId, VehicleDocumentKind kind);
}

interface VehicleVerificationRepository extends JpaRepository<VehicleVerification, UUID> {

    /** Every invitation this vehicle has ever had — the cap is a count over
     *  these, and the "is one still out?" check is a filter over them. Small by
     *  construction: the cap is three. */
    List<VehicleVerification> findByVehicleIdOrderByCreatedAtDesc(UUID vehicleId);

    List<VehicleVerification> findByPassengerIdOrderByCreatedAtDesc(UUID passengerId);

    /** The sweep: invitations nobody answered in time. */
    @Query("select v from VehicleVerification v where v.status = :status "
        + "and v.expiresAt <= :now order by v.expiresAt asc")
    List<VehicleVerification> lapsed(@Param("status") VerificationStatus status,
                                     @Param("now") java.time.OffsetDateTime now, Pageable page);
}

interface VehiclePhotoRepository extends JpaRepository<VehiclePhoto, VehiclePhoto.Key> {

    List<VehiclePhoto> findByVehicleIdOrderBySortOrderAsc(UUID vehicleId);

    List<VehiclePhoto> findByVehicleIdInOrderBySortOrderAsc(Collection<UUID> vehicleIds);

    void deleteByVehicleId(UUID vehicleId);
}
