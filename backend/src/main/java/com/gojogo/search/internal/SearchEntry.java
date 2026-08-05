package com.gojogo.search.internal;

import com.gojogo.search.SearchDocument;
import com.gojogo.search.SearchKind;
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
 * One indexed thing. The {@code tsv} column is generated in the database and
 * deliberately unmapped — Java never computes or carries the vector.
 */
@Entity
@Table(name = "document", schema = "search")
class SearchEntry {

    @Id
    @GeneratedValue
    private UUID id;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, length = 24)
    private SearchKind kind;

    @Column(name = "ref_id", nullable = false)
    private UUID refId;

    @Column(name = "title", nullable = false)
    private String title = "";

    @Column(name = "body", nullable = false)
    private String body = "";

    @Column(name = "category", nullable = false)
    private String category = "";

    @Column(name = "owner_id")
    private UUID ownerId;

    @Column(name = "popularity", nullable = false)
    private long popularity;

    @Column(name = "active", nullable = false)
    private boolean active = true;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt = OffsetDateTime.now();

    protected SearchEntry() {
    }

    SearchEntry(SearchKind kind, UUID refId) {
        this.kind = kind;
        this.refId = refId;
    }

    void apply(SearchDocument document) {
        this.title = document.title() == null ? "" : document.title();
        this.body = document.body() == null ? "" : document.body();
        this.category = document.category() == null ? "" : document.category();
        this.ownerId = document.ownerId();
        this.popularity = Math.max(0, document.popularity());
        this.active = document.active();
        this.updatedAt = OffsetDateTime.now();
    }

    UUID getId() {
        return id;
    }

    SearchKind getKind() {
        return kind;
    }

    UUID getRefId() {
        return refId;
    }

    String getTitle() {
        return title;
    }

    String getBody() {
        return body;
    }

    String getCategory() {
        return category;
    }

    UUID getOwnerId() {
        return ownerId;
    }

    long getPopularity() {
        return popularity;
    }

    boolean isActive() {
        return active;
    }

    OffsetDateTime getUpdatedAt() {
        return updatedAt;
    }
}
