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

    /** Engagement earned recently, decaying with age. See V50 for the shape. */
    @Column(name = "trend_score", nullable = false)
    private double trendScore;

    @Column(name = "sampled_popularity", nullable = false)
    private long sampledPopularity;

    /** Null until the first sample, which only sets a baseline. */
    @Column(name = "sampled_at")
    private OffsetDateTime sampledAt;

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

    double getTrendScore() {
        return trendScore;
    }

    long getSampledPopularity() {
        return sampledPopularity;
    }

    OffsetDateTime getSampledAt() {
        return sampledAt;
    }

    /**
     * Folds one observation of the live counter into the decaying score.
     *
     * <p>Deliberately does not touch {@code updatedAt}: that column means "the
     * thing itself changed" and is the rail's last tiebreaker. A recompute
     * running every quarter hour and stamping it would make every document
     * permanently look freshly edited, which is a worse version of the bug
     * this is here to fix.
     *
     * <p>A drop in the counter — an unlike, a withdrawn rating — contributes
     * zero rather than a negative: the score measures engagement gained, and
     * letting it go negative would rank a thing people are backing away from
     * below one nobody has touched at all.
     */
    void sample(long livePopularity, OffsetDateTime now, double halfLifeMinutes) {
        long observed = Math.max(0, livePopularity);
        if (sampledAt == null) {
            // Baseline only. See V50.
            this.trendScore = 0;
        } else {
            long gained = Math.max(0, observed - sampledPopularity);
            double elapsed = Math.max(0,
                java.time.Duration.between(sampledAt, now).toMillis() / 60_000.0);
            double decay = halfLifeMinutes <= 0 ? 0 : Math.pow(0.5, elapsed / halfLifeMinutes);
            this.trendScore = gained + trendScore * decay;
        }
        this.popularity = observed;
        this.sampledPopularity = observed;
        this.sampledAt = now;
    }

    /** The thing is gone or hidden: stop ranking it, keep the row's history. */
    void deactivate() {
        this.active = false;
        this.trendScore = 0;
    }
}
