package com.gojogo.services.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/** A verified-booking review — {@code economy.review}'s shape one vertical
 *  over, riding a COMPLETED booking instead of a completed order. */
@Entity
@Table(name = "review", schema = "services")
class ServiceReview {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "service_id", nullable = false)
    private UUID serviceId;

    @Column(name = "booking_id", nullable = false)
    private UUID bookingId;

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

    protected ServiceReview() {
    }

    ServiceReview(UUID serviceId, UUID bookingId, UUID authorId, int rating, String body) {
        this.serviceId = serviceId;
        this.bookingId = bookingId;
        this.authorId = authorId;
        this.rating = rating;
        this.body = body == null ? "" : body;
    }

    void amend(UUID bookingId, int rating, String body) {
        this.bookingId = bookingId;
        this.rating = rating;
        this.body = body == null ? "" : body;
        this.updatedAt = OffsetDateTime.now();
    }

    void reply(String body) {
        this.replyBody = body;
        this.repliedAt = OffsetDateTime.now();
    }

    UUID getId() {
        return id;
    }

    UUID getServiceId() {
        return serviceId;
    }

    UUID getBookingId() {
        return bookingId;
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
}
