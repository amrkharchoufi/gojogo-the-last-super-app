package com.gojogo.payments.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * What the platform takes from one vertical, from a given date.
 *
 * <p>Effective-dated rather than a plain config key because a fee change must
 * not retroactively change what an order that already settled was worth. The
 * row that applies to a settlement is the newest one that had taken effect when
 * it happened.
 */
@Entity
@Table(name = "fee_policy", schema = "payments")
class FeePolicy {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "vertical", nullable = false)
    private String vertical;

    @Column(name = "percent_bps", nullable = false)
    private int percentBps;

    @Column(name = "fixed_minor", nullable = false)
    private int fixedMinor;

    @Column(name = "effective_from", nullable = false)
    private OffsetDateTime effectiveFrom = OffsetDateTime.now();

    @Column(name = "note", nullable = false)
    private String note = "";

    protected FeePolicy() {
    }

    /** Rows arrive by migration, not from code — this exists so the arithmetic
     *  below can be tested without a database. */
    FeePolicy(String vertical, int percentBps, int fixedMinor) {
        this.vertical = vertical;
        this.percentBps = percentBps;
        this.fixedMinor = fixedMinor;
    }

    /**
     * The cut of {@code baseMinor}, rounded <em>down</em>. A half-cent always
     * goes to the party that earned the money rather than to the platform: it
     * is one cent per order, and being on the wrong side of that arithmetic is
     * not worth explaining to anybody.
     */
    long feeOn(long baseMinor) {
        if (baseMinor <= 0) return 0;
        long fee = Math.floorDiv(baseMinor * percentBps, 10_000L) + fixedMinor;
        return Math.min(fee, baseMinor);
    }

    int getPercentBps() {
        return percentBps;
    }

    int getFixedMinor() {
        return fixedMinor;
    }

    String getVertical() {
        return vertical;
    }
}
