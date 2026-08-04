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

    /** Whose bag this line is in (Phase 4 M3). The parent reference stays —
     *  a receipt is still read flat. */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "sub_order_id", nullable = false)
    private SubOrder subOrder;

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

    OrderLine(CustomerOrder order, SubOrder subOrder, UUID menuItemId, String name,
              int unitPriceCents, int qty, int sortOrder) {
        this.order = order;
        this.subOrder = subOrder;
        this.menuItemId = menuItemId;
        this.name = name;
        this.unitPriceCents = unitPriceCents;
        this.qty = qty;
        this.sortOrder = sortOrder;
    }

    SubOrder getSubOrder() {
        return subOrder;
    }

    /** Whether this line is in the given slice's bag. Identity first, id
     *  second: a freshly built order has no ids yet, and within a persistence
     *  context the same row is the same instance anyway. */
    boolean belongsTo(SubOrder slice) {
        if (subOrder == null || slice == null) return false;
        if (subOrder == slice) return true;
        return slice.getId() != null && slice.getId().equals(subOrder.getId());
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
