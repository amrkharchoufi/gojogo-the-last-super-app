package com.gojogo.payments.internal;

import com.gojogo.payments.Bucket;
import com.gojogo.payments.OwnerKind;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * One owner's balance in one bucket.
 *
 * <p>The balance is materialised rather than summed from the entries: a
 * checkout reads it, and summing an append-only table that grows forever gets
 * slower forever. {@code LedgerAuditJob} is what keeps the shortcut honest — it
 * re-derives every balance from the entries and shouts if one has drifted.
 *
 * <p>Rows are created by an {@code INSERT … ON CONFLICT DO NOTHING} in the
 * repository rather than by find-then-save: two first-ever movements for the
 * same person race otherwise, and the loser sees a constraint violation in the
 * middle of a payment.
 */
@Entity
@Table(name = "account", schema = "payments")
class Account {

    @Id
    @Column(name = "id", nullable = false)
    private UUID id;

    @Enumerated(EnumType.STRING)
    @Column(name = "owner_kind", nullable = false)
    private OwnerKind ownerKind;

    @Column(name = "owner_id", nullable = false)
    private UUID ownerId;

    @Enumerated(EnumType.STRING)
    @Column(name = "bucket", nullable = false)
    private Bucket bucket;

    @Column(name = "currency", nullable = false)
    private String currency;

    @Column(name = "balance_minor", nullable = false)
    private long balanceMinor;

    @Column(name = "allow_negative", nullable = false)
    private boolean allowNegative;

    /**
     * Optimistic locking on top of the pessimistic read the ledger takes. Belt
     * and braces on purpose: the row lock is what serialises two concurrent
     * debits, and this is what catches anything that changes a balance without
     * taking it.
     */
    @Version
    @Column(name = "version", nullable = false)
    private long version;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt = OffsetDateTime.now();

    protected Account() {
    }

    /** @throws com.gojogo.payments.InsufficientFundsException never — the
     *  caller checks first, because only it knows how to phrase the refusal */
    void add(long deltaMinor) {
        this.balanceMinor += deltaMinor;
        this.updatedAt = OffsetDateTime.now();
    }

    boolean canCover(long amountMinor) {
        return allowNegative || balanceMinor >= amountMinor;
    }

    UUID getId() {
        return id;
    }

    OwnerKind getOwnerKind() {
        return ownerKind;
    }

    UUID getOwnerId() {
        return ownerId;
    }

    Bucket getBucket() {
        return bucket;
    }

    String getCurrency() {
        return currency;
    }

    long getBalanceMinor() {
        return balanceMinor;
    }
}
