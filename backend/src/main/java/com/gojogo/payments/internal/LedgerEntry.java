package com.gojogo.payments.internal;

import com.gojogo.payments.LedgerKind;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * One movement. Append-only — there is no setter here and no update path
 * anywhere, because an edited ledger cannot be audited. A mistake is corrected
 * by another entry ({@link LedgerKind#ADJUSTMENT}).
 *
 * <p>Money leaves {@code debitAccountId} and lands in {@code creditAccountId}.
 * Both sides always exist, which is what makes the sum of all balances a
 * constant and a missing counterparty impossible to write down.
 */
@Entity
@Table(name = "ledger_entry", schema = "payments")
class LedgerEntry {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "idempotency_key", nullable = false, updatable = false)
    private String idempotencyKey;

    @Column(name = "debit_account_id", nullable = false, updatable = false)
    private UUID debitAccountId;

    @Column(name = "credit_account_id", nullable = false, updatable = false)
    private UUID creditAccountId;

    @Column(name = "amount_minor", nullable = false, updatable = false)
    private long amountMinor;

    @Column(name = "currency", nullable = false, updatable = false)
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, updatable = false)
    private LedgerKind kind;

    @Column(name = "ref_kind", nullable = false, updatable = false)
    private String refKind = "";

    @Column(name = "ref_id", updatable = false)
    private UUID refId;

    @Column(name = "memo", nullable = false, updatable = false)
    private String memo = "";

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    protected LedgerEntry() {
    }

    LedgerEntry(String idempotencyKey, UUID debitAccountId, UUID creditAccountId,
                long amountMinor, String currency, LedgerKind kind,
                String refKind, UUID refId, String memo) {
        this.idempotencyKey = idempotencyKey;
        this.debitAccountId = debitAccountId;
        this.creditAccountId = creditAccountId;
        this.amountMinor = amountMinor;
        this.currency = currency;
        this.kind = kind;
        this.refKind = refKind == null ? "" : refKind;
        this.refId = refId;
        // Truncated rather than rejected: a memo is a courtesy, and no payment
        // should fail because a restaurant has a long name.
        this.memo = memo == null ? "" : memo.substring(0, Math.min(memo.length(), 200));
        this.createdAt = OffsetDateTime.now();
    }

    UUID getId() {
        return id;
    }

    UUID getDebitAccountId() {
        return debitAccountId;
    }

    UUID getCreditAccountId() {
        return creditAccountId;
    }

    long getAmountMinor() {
        return amountMinor;
    }

    String getCurrency() {
        return currency;
    }

    LedgerKind getKind() {
        return kind;
    }

    String getRefKind() {
        return refKind;
    }

    UUID getRefId() {
        return refId;
    }

    String getMemo() {
        return memo;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }
}
