package com.gojogo.economy.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import java.util.UUID;

/** One bought variant, snapshotted — the catalog changing under an old order
 *  changes nothing about what was bought or what it cost. */
@Entity
@Table(name = "product_order_line", schema = "economy")
class ProductOrderLine {

    @Id
    @GeneratedValue
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "order_id")
    private ProductOrder order;

    @Column(name = "product_id", nullable = false)
    private UUID productId;

    @Column(name = "variant_id", nullable = false)
    private UUID variantId;

    @Column(name = "product_name", nullable = false)
    private String productName;

    @Column(name = "variant_label", nullable = false)
    private String variantLabel;

    @Column(name = "unit_price_cents", nullable = false)
    private long unitPriceCents;

    @Column(name = "quantity", nullable = false)
    private int quantity;

    @Column(name = "line_total_cents", nullable = false)
    private long lineTotalCents;

    protected ProductOrderLine() {
    }

    ProductOrderLine(ProductOrder order, UUID productId, UUID variantId, String productName,
                     String variantLabel, long unitPriceCents, int quantity) {
        this.order = order;
        this.productId = productId;
        this.variantId = variantId;
        this.productName = productName;
        this.variantLabel = variantLabel;
        this.unitPriceCents = unitPriceCents;
        this.quantity = quantity;
        this.lineTotalCents = unitPriceCents * quantity;
    }

    UUID getProductId() {
        return productId;
    }

    UUID getVariantId() {
        return variantId;
    }

    String getProductName() {
        return productName;
    }

    String getVariantLabel() {
        return variantLabel;
    }

    long getUnitPriceCents() {
        return unitPriceCents;
    }

    int getQuantity() {
        return quantity;
    }

    long getLineTotalCents() {
        return lineTotalCents;
    }
}
