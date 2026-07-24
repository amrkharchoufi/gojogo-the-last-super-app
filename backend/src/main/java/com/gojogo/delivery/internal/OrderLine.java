package com.gojogo.delivery.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import java.util.UUID;

/**
 * A line of a placed order. Name and unit price are <em>copied</em> from the
 * menu item at order time: the receipt must not change when the restaurant
 * re-prices or renames a dish tomorrow.
 */
@Entity
@Table(name = "order_line", schema = "delivery")
class OrderLine {

    @Id
    @GeneratedValue
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "order_id", nullable = false)
    private CustomerOrder order;

    @Column(name = "menu_item_id", nullable = false)
    private UUID menuItemId;

    @Column(name = "name", nullable = false)
    private String name;

    @Column(name = "unit_price_cents", nullable = false)
    private int unitPriceCents;

    @Column(name = "qty", nullable = false)
    private int qty;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    protected OrderLine() {
    }

    OrderLine(CustomerOrder order, UUID menuItemId, String name, int unitPriceCents, int qty, int sortOrder) {
        this.order = order;
        this.menuItemId = menuItemId;
        this.name = name;
        this.unitPriceCents = unitPriceCents;
        this.qty = qty;
        this.sortOrder = sortOrder;
    }

    UUID getMenuItemId() {
        return menuItemId;
    }

    String getName() {
        return name;
    }

    int getUnitPriceCents() {
        return unitPriceCents;
    }

    int getQty() {
        return qty;
    }

    int lineTotalCents() {
        return unitPriceCents * qty;
    }
}
