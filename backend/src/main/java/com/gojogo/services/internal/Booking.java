package com.gojogo.services.internal;

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
 * One appointment (SPECS §7). The price is a snapshot — of the service at
 * request, or of the quote at acceptance — and the money follows the state
 * machine: held while anything can still happen, settled only after the work
 * is done and the capture window has passed.
 */
@Entity
@Table(name = "booking", schema = "services")
class Booking {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "service_id", nullable = false)
    private UUID serviceId;

    @Column(name = "provider_id", nullable = false)
    private UUID providerId;

    @Column(name = "customer_id", nullable = false)
    private UUID customerId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 24)
    private BookingStatus status = BookingStatus.REQUESTED;

    @Column(name = "starts_at", nullable = false)
    private OffsetDateTime startsAt;

    @Column(name = "duration_minutes", nullable = false)
    private int durationMinutes;

    /** Null until a quote lands on a PRICE_ON_QUOTE booking. */
    @Column(name = "price_cents")
    private Long priceCents;

    @Enumerated(EnumType.STRING)
    @Column(name = "payment_status", nullable = false, length = 16)
    private BookingPaymentState paymentStatus = BookingPaymentState.NONE;

    @Column(name = "note", nullable = false)
    private String note = "";

    @Column(name = "conversation_id")
    private UUID conversationId;

    @Column(name = "cancellation_fee_cents", nullable = false)
    private long cancellationFeeCents;

    @Column(name = "requested_at", nullable = false)
    private OffsetDateTime requestedAt = OffsetDateTime.now();

    @Column(name = "quoted_at")
    private OffsetDateTime quotedAt;

    @Column(name = "confirmed_at")
    private OffsetDateTime confirmedAt;

    @Column(name = "completed_at")
    private OffsetDateTime completedAt;

    @Column(name = "declined_at")
    private OffsetDateTime declinedAt;

    @Column(name = "cancelled_at")
    private OffsetDateTime cancelledAt;

    @Column(name = "settled_at")
    private OffsetDateTime settledAt;

    @Column(name = "reminded_24h", nullable = false)
    private boolean reminded24h;

    @Column(name = "reminded_1h", nullable = false)
    private boolean reminded1h;

    protected Booking() {
    }

    Booking(UUID serviceId, UUID providerId, UUID customerId, OffsetDateTime startsAt,
            int durationMinutes, Long priceCents, String note) {
        this.serviceId = serviceId;
        this.providerId = providerId;
        this.customerId = customerId;
        this.startsAt = startsAt;
        this.durationMinutes = durationMinutes;
        this.priceCents = priceCents;
        this.note = note == null ? "" : note;
    }

    OffsetDateTime endsAt() {
        return startsAt.plusMinutes(durationMinutes);
    }

    boolean overlaps(OffsetDateTime from, OffsetDateTime to) {
        return startsAt.isBefore(to) && from.isBefore(endsAt());
    }

    void quoted(long priceCents, OffsetDateTime at) {
        this.priceCents = priceCents;
        this.quotedAt = at;
    }

    void held() {
        this.paymentStatus = BookingPaymentState.HELD;
    }

    void confirmed(OffsetDateTime at) {
        this.status = BookingStatus.CONFIRMED;
        this.confirmedAt = at;
    }

    void completed(OffsetDateTime at) {
        this.status = BookingStatus.COMPLETED;
        this.completedAt = at;
    }

    void declined(OffsetDateTime at) {
        this.status = BookingStatus.DECLINED;
        this.declinedAt = at;
    }

    void cancelled(BookingStatus how, long feeCents, OffsetDateTime at) {
        this.status = how;
        this.cancellationFeeCents = feeCents;
        this.cancelledAt = at;
    }

    void noShow(OffsetDateTime at) {
        this.status = BookingStatus.NO_SHOW;
        this.cancellationFeeCents = priceCents == null ? 0 : priceCents;
        this.cancelledAt = at;
    }

    void settled(OffsetDateTime at) {
        this.paymentStatus = BookingPaymentState.SETTLED;
        this.settledAt = at;
    }

    void releasedFunds(OffsetDateTime at) {
        this.paymentStatus = BookingPaymentState.RELEASED;
        this.settledAt = at;
    }

    void conversation(UUID conversationId) {
        this.conversationId = conversationId;
    }

    void reminded(int hoursAhead) {
        if (hoursAhead >= 24) this.reminded24h = true;
        else this.reminded1h = true;
    }

    UUID getId() {
        return id;
    }

    UUID getServiceId() {
        return serviceId;
    }

    UUID getProviderId() {
        return providerId;
    }

    UUID getCustomerId() {
        return customerId;
    }

    BookingStatus getStatus() {
        return status;
    }

    OffsetDateTime getStartsAt() {
        return startsAt;
    }

    int getDurationMinutes() {
        return durationMinutes;
    }

    Long getPriceCents() {
        return priceCents;
    }

    BookingPaymentState getPaymentStatus() {
        return paymentStatus;
    }

    String getNote() {
        return note;
    }

    UUID getConversationId() {
        return conversationId;
    }

    long getCancellationFeeCents() {
        return cancellationFeeCents;
    }

    OffsetDateTime getRequestedAt() {
        return requestedAt;
    }

    OffsetDateTime getQuotedAt() {
        return quotedAt;
    }

    OffsetDateTime getConfirmedAt() {
        return confirmedAt;
    }

    OffsetDateTime getCompletedAt() {
        return completedAt;
    }

    OffsetDateTime getCancelledAt() {
        return cancelledAt;
    }

    boolean isReminded24h() {
        return reminded24h;
    }

    boolean isReminded1h() {
        return reminded1h;
    }
}
