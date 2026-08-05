package com.gojogo.economy.internal;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * A verified-purchase review (SPECS §6). One per buyer per product — a second
 * purchase edits the review rather than stacking a duplicate, which is why the
 * unique index is on (product, author) and the order id is a provenance stamp
 * rather than part of the key.
 *
 * <p>The seller's reply is a column, because SPECS caps it at one per review —
 * a state that duplicates a table is a table.
 */
@Entity
@Table(name = "review", schema = "economy")
class ProductReview {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "product_id", nullable = false)
    private UUID productId;

    /** The completed order that makes this a verified purchase. */
    @Column(name = "order_id", nullable = false)
    private UUID orderId;

    @Column(name = "author_id", nullable = false)
    private UUID authorId;

    @Column(name = "rating", nullable = false)
    private int rating;

    @Column(name = "body", nullable = false)
    private String body = "";

    @Column(name = "reply_body")
    private String replyBody;

    @Column(name = "replied_at")
    private OffsetDateTime repliedAt;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "updated_at")
    private OffsetDateTime updatedAt;

    @OneToMany(mappedBy = "review", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    @OrderBy("sortOrder")
    private List<ProductReviewPhoto> photos = new ArrayList<>();

    protected ProductReview() {
    }

    ProductReview(UUID productId, UUID orderId, UUID authorId, int rating, String body) {
        this.productId = productId;
        this.orderId = orderId;
        this.authorId = authorId;
        this.rating = rating;
        this.body = body == null ? "" : body;
    }

    void amend(UUID orderId, int rating, String body) {
        this.orderId = orderId;
        this.rating = rating;
        this.body = body == null ? "" : body;
        this.updatedAt = OffsetDateTime.now();
    }

    void reply(String body) {
        this.replyBody = body;
        this.repliedAt = OffsetDateTime.now();
    }

    void replacePhotos(List<String> imageUrls) {
        photos.clear();
        for (int i = 0; i < imageUrls.size(); i++) {
            photos.add(new ProductReviewPhoto(this, i, imageUrls.get(i)));
        }
    }

    UUID getId() {
        return id;
    }

    UUID getProductId() {
        return productId;
    }

    UUID getOrderId() {
        return orderId;
    }

    UUID getAuthorId() {
        return authorId;
    }

    int getRating() {
        return rating;
    }

    String getBody() {
        return body;
    }

    String getReplyBody() {
        return replyBody;
    }

    OffsetDateTime getRepliedAt() {
        return repliedAt;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    List<ProductReviewPhoto> getPhotos() {
        return photos;
    }
}
