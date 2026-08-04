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

    @Column(name = "total_cents", nullable = false)
    private int totalCents;

    /**
     * What per-sub-order cancellations have already given back out of the hold
     * (Phase 4 M3). Settlement insists that what it splits plus this equals
     * what was held — the same "nothing strands in escrow" check as before,
     * taught about partial refunds.
     */
    @Column(name = "released_cents", nullable = false)
    private int releasedCents;

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

    /**
     * The dispatch registration carrying this, and the profile behind it. Both
     * copied onto the order at assignment rather than looked up on every read:
     * a receipt names whoever actually brought the food, and it goes on naming
     * them after they stop working here.
     */
    @Column(name = "courier_worker_id")
    private UUID courierWorkerId;

    @Column(name = "courier_user_id")
    private UUID courierUserId;

    /**
     * When the food is expected to be ready across every kitchen still cooking
     * — the latest accepted sub-order's own {@code readyAt}. This is what the
     * courier search is timed from, because a courier who arrives before the
     * slowest kitchen is done waits unpaid at a counter.
     */
    @Column(name = "ready_at")
    private OffsetDateTime readyAt;

    /** When the courier had every bag — the moment the parent enters DELIVERING.
     *  Each sub-order keeps its own {@code collectedAt} beside this. */
    @Column(name = "picked_up_at")
    private OffsetDateTime pickedUpAt;

    /**
     * The delivery PIN (Phase 4 M2): the one code that stayed on the order when
     * the pickup codes moved down to the sub-orders (Phase 4 M3), because there
     * is one door however many kitchens there were.
     *
     * <p>Stored, not derived — it must survive being read out — and shown to the
     * customer only, never on the courier's job: a code the courier can read is
     * a code that proves nothing. Blank means "no check to run" (pre-V38).
     */
    @Column(name = "delivery_pin", nullable = false)
    private String deliveryPin = "";

    /** The customer's choice of how it is handed over. PIN until they say
     *  otherwise, and changeable right up until the moment it happens. */
    @Enumerated(EnumType.STRING)
    @Column(name = "handoff_mode", nullable = false)
    private HandoffMode handoffMode = HandoffMode.PIN;

    /**
     * Wrong delivery PINs. Counted, unlike the pickup code's, because this is
     * the handoff that pays somebody — and kept on the row after the fallback
     * opens rather than reset, since the count is the only record that the
     * fallback was used and how it was reached.
     */
    @Column(name = "handoff_attempts", nullable = false)
    private int handoffAttempts;

    /** The drop-off photo's private object key — never a URL, never returned to
     *  a client, and always one the server itself minted. */
    @Column(name = "proof_photo_key")
    private String proofPhotoKey;

    /** The courier↔customer thread, opened at assignment. Nullable, and stays
     *  null when messaging was having a moment: a chat that did not open must
     *  never cost somebody their delivery. */
    @Column(name = "conversation_id")
    private UUID conversationId;

    @Enumerated(EnumType.STRING)
    @Column(name = "courier_search", nullable = false)
    private CourierSearch courierSearch = CourierSearch.NONE;

    /** Why it ended, when it ended badly. Shown to the customer verbatim, so it
     *  is written for them and not for a log. */
    @Column(name = "cancel_reason", nullable = false)
    private String cancelReason = "";

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

    /** One per merchant (Phase 4 M3). Every order has at least one. */
    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    @OrderBy("sortOrder")
    private List<SubOrder> subOrders = new ArrayList<>();

    protected CustomerOrder() {
    }

    CustomerOrder(UUID userId, String currency, String note, OffsetDateTime etaAt) {
        this.userId = userId;
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

    void addLine(SubOrder subOrder, UUID menuItemId, String name, int unitPriceCents, int qty) {
        lines.add(new OrderLine(this, subOrder, menuItemId, name, unitPriceCents, qty,
            lines.size()));
    }

    SubOrder addSubOrder(UUID merchantId, int subtotalCents, int deliveryFeeCents,
                         int discountCents, UUID promotionId, String promotionCode) {
        SubOrder subOrder = new SubOrder(this, merchantId, subtotalCents, deliveryFeeCents,
            discountCents, promotionId, promotionCode, subOrders.size());
        subOrders.add(subOrder);
        return subOrder;
    }

    /**
     * Stamps the priced order onto the row. The arithmetic lives in
     * {@link Basket} so that quoting and placing cannot drift apart — a quote
     * the customer approved and a total they were charged being computed by two
     * different code paths is how people get billed for surprises.
     */
    void priceIt(Basket basket) {
        this.subtotalCents = basket.subtotalCents();
        this.deliveryFeeCents = basket.deliveryFeeCents();
        this.serviceFeeCents = basket.serviceFeeCents();
        this.discountCents = basket.discountCents();
        this.tipCents = basket.tipCents();
        this.totalCents = basket.totalCents();
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

    /** A sub-order's share went back to the customer; the hold shrinks. */
    void partiallyReleased(int cents) {
        this.releasedCents += cents;
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

    void cancelledBecause(String reason) {
        this.cancelReason = reason == null ? "" : reason;
    }

    /**
     * Re-derives the order-level clock from the kitchens still cooking: ready
     * when the <em>last</em> of them is. Called whenever any sub-order's own
     * clock moves — an accept, a ready, a cancellation. Moving {@code readyAt}
     * matters even once the courier is found: it is what the pickup ETA on
     * their screen is drawn from, and a courier told the wrong time waits at a
     * counter or arrives at cold food.
     */
    void retime(OffsetDateTime readyAt, OffsetDateTime etaAt) {
        this.readyAt = readyAt;
        this.etaAt = etaAt;
    }

    void searchingForCourier() {
        this.courierSearch = CourierSearch.SEARCHING;
    }

    void noCourierFound() {
        this.courierSearch = CourierSearch.FAILED;
    }

    /** A real person, from a dispatch {@code Assignment}. */
    void assignCourier(UUID workerId, UUID userId, String name, String vehicle,
                       BigDecimal courierRating, int deliveries) {
        this.courierWorkerId = workerId;
        this.courierUserId = userId;
        this.courierName = name;
        this.courierVehicle = vehicle;
        this.courierRating = courierRating;
        this.courierDeliveries = deliveries;
        this.courierSearch = CourierSearch.ASSIGNED;
    }

    void pickedUp(OffsetDateTime at) {
        this.pickedUpAt = at;
    }

    /**
     * Mints the delivery PIN, once. Guarded rather than assigned, so that a
     * second accept — a retried request, a duplicated event, anything — cannot
     * change a number the customer has already read off their screen.
     * Re-minting would not be a smaller bug than not minting at all: it would
     * make a courier with the right PIN wrong.
     */
    void mintDeliveryPin(String pin) {
        if (deliveryPin.isBlank()) this.deliveryPin = pin;
    }

    void chooseHandoffMode(HandoffMode mode) {
        this.handoffMode = mode;
    }

    void handoffRefused() {
        this.handoffAttempts++;
    }

    void proofPhotographedAt(String objectKey) {
        this.proofPhotoKey = objectKey;
    }

    void attachConversation(UUID conversationId) {
        this.conversationId = conversationId;
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

    int getReleasedCents() {
        return releasedCents;
    }

    /** What is still held in escrow for this order — the amount a settlement
     *  or a full release has to account for, to the cent. */
    int heldRemainingCents() {
        return totalCents - releasedCents;
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

    UUID getCourierWorkerId() {
        return courierWorkerId;
    }

    UUID getCourierUserId() {
        return courierUserId;
    }

    OffsetDateTime getReadyAt() {
        return readyAt;
    }

    OffsetDateTime getPickedUpAt() {
        return pickedUpAt;
    }

    String getDeliveryPin() {
        return deliveryPin;
    }

    HandoffMode getHandoffMode() {
        return handoffMode;
    }

    int getHandoffAttempts() {
        return handoffAttempts;
    }

    String getProofPhotoKey() {
        return proofPhotoKey;
    }

    UUID getConversationId() {
        return conversationId;
    }

    CourierSearch getCourierSearch() {
        return courierSearch;
    }

    String getCancelReason() {
        return cancelReason;
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

    List<SubOrder> getSubOrders() {
        return subOrders;
    }

    /** The slices still somebody's problem — not delivered, not cancelled. */
    List<SubOrder> liveSubOrders() {
        return subOrders.stream().filter(s -> s.getStatus().isLive()).toList();
    }

    /** Every kitchen has answered — accepted or ended — so the courier search
     *  can be timed. A sub-order still CONFIRMED is a kitchen still deciding. */
    boolean allSubOrdersAnswered() {
        return subOrders.stream().noneMatch(s -> s.getStatus() == SubOrderStatus.CONFIRMED);
    }
}
