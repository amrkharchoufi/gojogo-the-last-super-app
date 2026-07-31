package com.gojogo.storefront.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * One page, stored whole.
 *
 * <p>The natural key is (surface, owner), but the row carries a generated id
 * anyway and the pair is a unique index instead. An entity with an assigned
 * composite id makes every save a merge — Hibernate has to SELECT before it can
 * decide between INSERT and UPDATE, and code that expected an insert quietly
 * gets an update instead. A generated id keeps "arrange a page for the first
 * time" and "rewrite it" the two different operations they are.
 *
 * <p>{@code blocks} is JSON in a {@code text} column, not {@code jsonb}. Nothing
 * queries inside the document — it is fetched whole by its owner and rendered —
 * so the only thing jsonb would add is a binding that cannot be tested on a
 * machine with no database. The shape is guaranteed by the validator on the way
 * in, which is a stronger guarantee than "it parses" anyway.
 */
@Entity
@Table(name = "document", schema = "storefront")
class StoredStorefront {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "surface", nullable = false, updatable = false, length = 32)
    private String surface;

    @Column(name = "owner_id", nullable = false, updatable = false)
    private UUID ownerId;

    /** The author's counter: 1 on the first save, +1 on each one after. */
    @Column(name = "doc_version", nullable = false)
    private int docVersion;

    @Column(name = "blocks", nullable = false)
    private String blocks = "[]";

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt = OffsetDateTime.now();

    /** Optimistic lock. Two page builders saving at once is exactly the case
     *  this module exists to serve, and the loser should be told rather than
     *  have their blocks silently win. */
    @Version
    @Column(name = "row_version", nullable = false)
    private long rowVersion;

    protected StoredStorefront() {
    }

    StoredStorefront(String surface, UUID ownerId) {
        this.surface = surface;
        this.ownerId = ownerId;
    }

    /** Replaces the page and bumps the version the author sees. */
    void rewrite(String blocks) {
        this.blocks = blocks;
        this.docVersion += 1;
        this.updatedAt = OffsetDateTime.now();
    }

    UUID getOwnerId() {
        return ownerId;
    }

    int getDocVersion() {
        return docVersion;
    }

    String getBlocks() {
        return blocks;
    }

    OffsetDateTime getUpdatedAt() {
        return updatedAt;
    }
}
