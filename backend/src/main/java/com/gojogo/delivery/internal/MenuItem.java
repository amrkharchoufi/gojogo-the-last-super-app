package com.gojogo.delivery.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.util.UUID;

@Entity
@Table(name = "menu_item", schema = "delivery")
class MenuItem {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "section_id", nullable = false, insertable = false, updatable = false)
    private UUID sectionId;

    @Column(name = "name", nullable = false)
    private String name;

    @Column(name = "detail", nullable = false)
    private String detail = "";

    @Column(name = "price_cents", nullable = false)
    private int priceCents;

    @Column(name = "image_url")
    private String imageUrl;

    @Column(name = "popular", nullable = false)
    private boolean popular;

    @Column(name = "available", nullable = false)
    private boolean available = true;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    protected MenuItem() {
    }

    UUID getId() {
        return id;
    }

    UUID getSectionId() {
        return sectionId;
    }

    String getName() {
        return name;
    }

    String getDetail() {
        return detail;
    }

    int getPriceCents() {
        return priceCents;
    }

    String getImageUrl() {
        return imageUrl;
    }

    boolean isPopular() {
        return popular;
    }

    boolean isAvailable() {
        return available;
    }

    int getSortOrder() {
        return sortOrder;
    }
}
