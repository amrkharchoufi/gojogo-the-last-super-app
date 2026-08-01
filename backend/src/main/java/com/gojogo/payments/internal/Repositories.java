package com.gojogo.payments.internal;

import com.gojogo.payments.Bucket;
import com.gojogo.payments.OwnerKind;
import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

interface AccountRepository extends JpaRepository<Account, UUID> {

    /**
     * Creates the account if it isn't there, and does nothing if it is.
     *
     * <p>Native and {@code ON CONFLICT DO NOTHING} because find-then-save races:
     * two first-ever movements for the same person would both find nothing, both
     * insert, and one would blow up in the middle of a payment. Letting the
     * database arbitrate is the only version of this that is actually correct.
     */
    @Modifying
    @Query(value = """
        INSERT INTO payments.account (owner_kind, owner_id, bucket, currency, allow_negative)
        VALUES (:ownerKind, :ownerId, :bucket, :currency, :allowNegative)
        ON CONFLICT (owner_kind, owner_id, bucket, currency) DO NOTHING
        """, nativeQuery = true)
    void ensure(@Param("ownerKind") String ownerKind, @Param("ownerId") UUID ownerId,
                @Param("bucket") String bucket, @Param("currency") String currency,
                @Param("allowNegative") boolean allowNegative);

    Optional<Account> findByOwnerKindAndOwnerIdAndBucketAndCurrency(
        OwnerKind ownerKind, UUID ownerId, Bucket bucket, String currency);

    /**
     * The read a movement takes. {@code PESSIMISTIC_WRITE} is what serialises
     * two concurrent debits of the same account — without it both read the same
     * starting balance, both decide it is sufficient, and the account ends up
     * negative with two entries that each looked fine.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
        select a from Account a
        where a.ownerKind = :ownerKind and a.ownerId = :ownerId
          and a.bucket = :bucket and a.currency = :currency
        """)
    Optional<Account> lock(@Param("ownerKind") OwnerKind ownerKind, @Param("ownerId") UUID ownerId,
                           @Param("bucket") Bucket bucket, @Param("currency") String currency);

    List<Account> findByOwnerKindAndOwnerIdAndCurrency(
        OwnerKind ownerKind, UUID ownerId, String currency);
}

interface LedgerEntryRepository extends JpaRepository<LedgerEntry, UUID> {

    Optional<LedgerEntry> findByIdempotencyKey(String idempotencyKey);

    boolean existsByIdempotencyKey(String idempotencyKey);

    /** How many times an operation with this prefix has already happened — how
     *  a repeatable purchase derives its next key from a fact rather than a
     *  clock. The unique index on the column serves the prefix scan. */
    long countByIdempotencyKeyStartingWith(String prefix);

    List<LedgerEntry> findByRefKindAndRefIdOrderByCreatedAtAsc(String refKind, UUID refId);

    /** A statement: an account shows up on either side of an entry, so both
     *  sides are searched and the caller works out the sign. */
    @Query("""
        select e from LedgerEntry e
        where e.debitAccountId in :accountIds or e.creditAccountId in :accountIds
        order by e.createdAt desc
        """)
    List<LedgerEntry> statement(@Param("accountIds") List<UUID> accountIds, Pageable page);

    /** What the entries say an account's balance should be. Read only by
     *  {@link LedgerAuditJob} — everything else trusts the materialised one. */
    @Query("""
        select coalesce(sum(case when e.creditAccountId = :accountId then e.amountMinor
                                 else -e.amountMinor end), 0)
        from LedgerEntry e
        where e.debitAccountId = :accountId or e.creditAccountId = :accountId
        """)
    long derivedBalance(@Param("accountId") UUID accountId);
}

interface StripePaymentRepository extends JpaRepository<StripePayment, UUID> {

    Optional<StripePayment> findBySessionId(String sessionId);

    List<StripePayment> findByUserIdOrderByCreatedAtDesc(UUID userId, Pageable page);

    /** Sessions that were never paid and can no longer be — swept to EXPIRED so
     *  a wallet screen doesn't show a "pending" top-up from last month. */
    List<StripePayment> findByStatusAndCreatedAtBefore(StripePayment.Status status,
                                                       OffsetDateTime before);
}

interface StripeEventRepository extends JpaRepository<StripeEvent, String> {
}

interface FeePolicyRepository extends JpaRepository<FeePolicy, UUID> {

    /** The policy in force at {@code at}, newest first — the caller takes the
     *  head. A vertical with no policy row takes no fee, which is the safe
     *  direction to be wrong in. */
    @Query("""
        select p from FeePolicy p
        where p.vertical = :vertical and p.effectiveFrom <= :at
        order by p.effectiveFrom desc
        """)
    List<FeePolicy> inForce(@Param("vertical") String vertical,
                            @Param("at") OffsetDateTime at, Pageable page);
}

interface TokenPackRepository extends JpaRepository<TokenPack, UUID> {

    /** What is on sale, in the order the seed row asked for. Sorted in the
     *  query rather than the client so every surface shows the same shelf. */
    List<TokenPack> findByActiveTrueOrderBySortOrderAsc();
}

interface ConnectAccountRepository extends JpaRepository<ConnectAccount, UUID> {

    Optional<ConnectAccount> findByOwnerKindAndOwnerId(OwnerKind ownerKind, UUID ownerId);
}

interface PayoutRepository extends JpaRepository<Payout, UUID> {

    List<Payout> findByOwnerKindAndOwnerIdOrderByCreatedAtDesc(
        OwnerKind ownerKind, UUID ownerId, Pageable page);

    /** The cooldown check: the last payout that actually went out. */
    Optional<Payout> findFirstByOwnerKindAndOwnerIdAndStatusOrderByCreatedAtDesc(
        OwnerKind ownerKind, UUID ownerId, Payout.Status status);
}
