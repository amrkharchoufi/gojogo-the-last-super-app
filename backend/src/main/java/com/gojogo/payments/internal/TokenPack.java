package com.gojogo.payments.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * A quantity of tokens at a price.
 *
 * <p>The only arithmetic on it is the bonus, and it is worth being explicit
 * about: a pack that costs less than its tokens are worth is a discount, and a
 * discount in a double-entry ledger has to come from somewhere. So the driver
 * pays {@code priceMinor} out of AVAILABLE, and the difference is a second entry
 * <em>from the platform</em>. Nothing is created, and a statement says plainly
 * who gave what.
 */
@Entity
@Table(name = "token_pack", schema = "payments")
class TokenPack {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(nullable = false, length = 60)
    private String name;

    @Column(nullable = false)
    private int tokens;

    @Column(name = "price_minor", nullable = false)
    private long priceMinor;

    @Column(nullable = false)
    private boolean active = true;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Column(nullable = false, length = 200)
    private String note = "";

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    protected TokenPack() {
    }

    /** What the tokens in this pack are worth at the current token value. */
    long faceValueMinor(long minorPerToken) {
        return tokens * Math.max(0, minorPerToken);
    }

    /**
     * The platform's share of the purchase — never negative.
     *
     * <p>A pack priced <em>above</em> face value is a configuration mistake
     * rather than a negative bonus: the driver simply pays it and gets the
     * tokens, because refusing to sell would be a worse answer to a typo in a
     * seed row than charging what the row says.
     */
    long bonusMinor(long minorPerToken) {
        return Math.max(0, faceValueMinor(minorPerToken) - priceMinor);
    }

    UUID getId() { return id; }

    String getName() { return name; }

    int getTokens() { return tokens; }

    long getPriceMinor() { return priceMinor; }

    boolean isActive() { return active; }

    String getNote() { return note; }
}
