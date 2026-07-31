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

    /** 100% the courier's at settlement, never split (SPECS §1). */
    @Column(name = "tip_cents", nullable = false)
    private int tipCents;

    /**
     * What the promotion took off. Always deducted from the <em>merchant's</em>
     * side at settlement, including a free-delivery promotion: a merchant funds
     * their own campaign, and no discount a restaurant chooses to run may reduce
     * what the courier or the platform is paid. One rule, one column, and a
     * receipt that adds up.
     */
    @Column(name = "discount_cents", nullable = false)
    private int discountCents;

    @Column(name = "promotion_id")
    private UUID promotionId;

    /** Copied, like the address: a receipt keeps saying WELCOME10 after the
     *  promotion is deleted. */
    @Column(name = "promotion_code", nullable = false)
    private String promotionCode = "";

    @Column(name = "total_cents", nullable = false)
    private int totalCents;

    /**
     * Where the money is. UNPAID is not a null — it is what an order placed
     * before the wallet existed genuinely was, and those orders are still in the
     * table.
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "payment_status", nullable = false)
    private PaymentStatus paymentStatus = PaymentStatus.UNPAID;

    /** When the funds were held. */
    @Column(name = "paid_at")
    private OffsetDateTime paidAt;

    /** When they were split among merchant, courier and platform. */
    @Column(name = "settled_at")
    private OffsetDateTime settledAt;

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

    /**
     * Stamps the priced basket onto the order. The arithmetic lives in
     * {@link Basket} so that quoting and placing cannot drift apart — a quote
     * the customer approved and a total they were charged being computed by two
     * different code paths is how people get billed for surprises.
     */
    void priceIt(Basket basket, UUID promotionId, String promotionCode) {
        this.subtotalCents = basket.subtotalCents();
        this.deliveryFeeCents = basket.deliveryFeeCents();
        this.serviceFeeCents = basket.serviceFeeCents();
        this.discountCents = basket.discountCents();
        this.tipCents = basket.tipCents();
        this.totalCents = basket.totalCents();
        this.promotionId = promotionId;
        this.promotionCode = promotionCode == null ? "" : promotionCode;
    }

    void held(OffsetDateTime at) {
        this.paymentStatus = PaymentStatus.HELD;
        this.paidAt = at;
    }

    void settled(OffsetDateTime at) {
        this.paymentStatus = PaymentStatus.CAPTURED;
        this.settledAt = at;
    }

    void releasedFunds(OffsetDateTime at) {
        this.paymentStatus = PaymentStatus.RELEASED;
        this.settledAt = at;
    }

    /** A tip added after delivery is settled straight through, so it lands on
     *  the total without going near escrow. */
    void tipped(int extraCents) {
        this.tipCents += extraCents;
        this.totalCents += extraCents;
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

    int getTipCents() {
        return tipCents;
    }

    int getDiscountCents() {
        return discountCents;
    }

    String getPromotionCode() {
        return promotionCode;
    }

    UUID getPromotionId() {
        return promotionId;
    }

    PaymentStatus getPaymentStatus() {
        return paymentStatus;
    }

    OffsetDateTime getPaidAt() {
        return paidAt;
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
