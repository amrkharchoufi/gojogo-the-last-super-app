package com.gojogo.delivery.internal;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * A customer's delivery order. Table is {@code customer_order} — {@code order}
 * is reserved in SQL.
 */
@Entity
@Table(name = "customer_order", schema = "delivery")
class CustomerOrder {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "merchant_id", nullable = false)
    private UUID merchantId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private OrderStatus status = OrderStatus.CONFIRMED;

    @Column(name = "subtotal_cents", nullable = false)
    private int subtotalCents;

    @Column(name = "delivery_fee_cents", nullable = false)
    private int deliveryFeeCents;

    @Column(name = "service_fee_cents", nullable = false)
    private int serviceFeeCents;

    @Column(name = "total_cents", nullable = false)
    private int totalCents;

    @Column(name = "currency", nullable = false)
    private String currency = "USD";

    @Column(name = "address_label", nullable = false)
    private String addressLabel = "";

    /** Which saved address this went to — kept for reference only; the copy
     *  below is what the receipt shows even if that address is later edited. */
    @Column(name = "address_id")
    private UUID addressId;

    @Column(name = "address_line", nullable = false)
    private String addressLine = "";

    @Column(name = "address_note", nullable = false)
    private String addressNote = "";

    @Column(name = "address_latitude")
    private Double addressLatitude;

    @Column(name = "address_longitude")
    private Double addressLongitude;

    @Column(name = "note", nullable = false)
    private String note = "";

    @Column(name = "courier_name")
    private String courierName;

    @Column(name = "courier_vehicle")
    private String courierVehicle;

    @Column(name = "courier_rating")
    private BigDecimal courierRating;

    @Column(name = "courier_deliveries")
    private Integer courierDeliveries;

    @Column(name = "rating")
    private Integer rating;

    @Column(name = "placed_at", nullable = false)
    private OffsetDateTime placedAt;

    @Column(name = "status_changed_at", nullable = false)
    private OffsetDateTime statusChangedAt;

    /** When the order is expected at the door — drives the countdown the app shows. */
    @Column(name = "eta_at", nullable = false)
    private OffsetDateTime etaAt;

    @Column(name = "closed_at")
    private OffsetDateTime closedAt;

    /** Guards against two backend instances advancing the same order at once. */
    @Version
    @Column(name = "version", nullable = false)
    private int version;

    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    @OrderBy("sortOrder")
    private List<OrderLine> lines = new ArrayList<>();

    protected CustomerOrder() {
    }

    CustomerOrder(UUID userId, UUID merchantId, String currency, String note,
                  OffsetDateTime etaAt) {
        this.userId = userId;
        this.merchantId = merchantId;
        this.currency = currency == null || currency.isBlank() ? "USD" : currency;
        this.note = note == null ? "" : note;
        this.placedAt = OffsetDateTime.now();
        this.statusChangedAt = this.placedAt;
        this.etaAt = etaAt;
    }

    /** Copies the chosen address onto the order (see the field comment). */
    void deliverTo(UUID addressId, String label, String line, String note,
                   Double latitude, Double longitude) {
        this.addressId = addressId;
        this.addressLabel = label == null ? "" : label;
        this.addressLine = line == null ? "" : line;
        this.addressNote = note == null ? "" : note;
        this.addressLatitude = latitude;
        this.addressLongitude = longitude;
    }

    void addLine(UUID menuItemId, String name, int unitPriceCents, int qty) {
        lines.add(new OrderLine(this, menuItemId, name, unitPriceCents, qty, lines.size()));
    }

    void priceIt(int deliveryFeeCents, int serviceFeeCents) {
        this.subtotalCents = lines.stream().mapToInt(OrderLine::lineTotalCents).sum();
        this.deliveryFeeCents = deliveryFeeCents;
        this.serviceFeeCents = serviceFeeCents;
        this.totalCents = this.subtotalCents + deliveryFeeCents + serviceFeeCents;
    }

    void moveTo(OrderStatus next, OffsetDateTime at) {
        this.status = next;
        this.statusChangedAt = at;
        if (next.isTerminal()) {
            this.closedAt = at;
        }
    }

    void assignCourier(String name, String vehicle, BigDecimal courierRating, int deliveries) {
        this.courierName = name;
        this.courierVehicle = vehicle;
        this.courierRating = courierRating;
        this.courierDeliveries = deliveries;
    }

    void rate(int stars) {
        this.rating = stars;
    }

    UUID getId() {
        return id;
    }

    UUID getUserId() {
        return userId;
    }

    UUID getMerchantId() {
        return merchantId;
    }

    OrderStatus getStatus() {
        return status;
    }

    int getSubtotalCents() {
        return subtotalCents;
    }

    int getDeliveryFeeCents() {
        return deliveryFeeCents;
    }

    int getServiceFeeCents() {
        return serviceFeeCents;
    }

    int getTotalCents() {
        return totalCents;
    }

    String getCurrency() {
        return currency;
    }

    String getAddressLabel() {
        return addressLabel;
    }

    UUID getAddressId() {
        return addressId;
    }

    String getAddressLine() {
        return addressLine;
    }

    String getAddressNote() {
        return addressNote;
    }

    Double getAddressLatitude() {
        return addressLatitude;
    }

    Double getAddressLongitude() {
        return addressLongitude;
    }

    String getNote() {
        return note;
    }

    String getCourierName() {
        return courierName;
    }

    String getCourierVehicle() {
        return courierVehicle;
    }

    BigDecimal getCourierRating() {
        return courierRating;
    }

    Integer getCourierDeliveries() {
        return courierDeliveries;
    }

    Integer getRating() {
        return rating;
    }

    OffsetDateTime getPlacedAt() {
        return placedAt;
    }

    OffsetDateTime getStatusChangedAt() {
        return statusChangedAt;
    }

    OffsetDateTime getEtaAt() {
        return etaAt;
    }

    List<OrderLine> getLines() {
        return lines;
    }
}
