package com.gojogo.travel.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * What a ride costs the <em>driver</em>, in tokens, for one category and one
 * distance band.
 *
 * <p>The other half of {@link PricingConfig}: that table says what the rider
 * pays, this one says what the driver pays to take it, and the two move
 * together. SPECS §4 puts this in {@code payments}; it lives here because it is
 * keyed on a vehicle category and a distance in metres — vocabulary a platform
 * money module has no business learning, and which it could only store as
 * strings it cannot check.
 *
 * <p><b>A band is an upper bound, not a range.</b> The winning row is the
 * cheapest {@code upToMetres} that still covers the trip, and each category ends
 * with a catch-all. Two columns of (min, max) can be left with a gap between
 * them, and a gap here is a ride that silently costs nothing.
 */
@Entity
@Table(name = "ride_token_price", schema = "travel")
class RideTokenPrice {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(nullable = false, length = 16)
    private String category;

    @Column(name = "up_to_metres", nullable = false)
    private int upToMetres;

    @Column(nullable = false)
    private int tokens;

    @Column(name = "effective_from", nullable = false)
    private OffsetDateTime effectiveFrom;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected RideTokenPrice() {
    }

    RideTokens.Band toBand() {
        return new RideTokens.Band(upToMetres, tokens);
    }

    String getCategory() { return category; }

    OffsetDateTime getEffectiveFrom() { return effectiveFrom; }
}
