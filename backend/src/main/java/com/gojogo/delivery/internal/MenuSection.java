package com.gojogo.delivery.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Entity
@Table(name = "menu_section", schema = "delivery")
class MenuSection {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "merchant_id", nullable = false)
    private UUID merchantId;

    @Column(name = "name", nullable = false)
    private String name;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    // Read-only side; MenuItem.sectionId writes the column (see Merchant.menu).
    @OneToMany(fetch = FetchType.LAZY)
    @JoinColumn(name = "section_id", insertable = false, updatable = false)
    @OrderBy("sortOrder")
    private List<MenuItem> items = new ArrayList<>();

    protected MenuSection() {
    }

    MenuSection(UUID merchantId, String name, int sortOrder) {
        this.merchantId = merchantId;
        this.name = name;
        this.sortOrder = sortOrder;
    }

    void rename(String name) {
        this.name = name;
    }

    void moveTo(int sortOrder) {
        this.sortOrder = sortOrder;
    }

    UUID getId() {
        return id;
    }

    UUID getMerchantId() {
        return merchantId;
    }

    String getName() {
        return name;
    }

    int getSortOrder() {
        return sortOrder;
    }

    List<MenuItem> getItems() {
        return items;
    }
}
