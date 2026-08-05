package com.gojogo.delivery.internal;

import com.gojogo.media.MediaDocumentApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.lang.reflect.Field;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.AdditionalAnswers.returnsFirstArg;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Reporting a problem with a delivered order, and answering one (Phase 4 M6).
 *
 * <p>Almost every test here is a <b>refusal</b>, and that is the shape of the
 * milestone rather than an accident of testing: a dispute refund is the only
 * thing in this system that takes money off somebody who has already been paid,
 * so what matters is not that it works but that it cannot be made to do the
 * wrong thing. Each refusal names a number, because the caller is an operator
 * deciding what to do next rather than a client to be told "no".
 */
class DisputeTests {

    private static final UUID CUSTOMER = UUID.randomUUID();
    private static final UUID SOMEONE_ELSE = UUID.randomUUID();
    private static final UUID MERCHANT = UUID.randomUUID();
    private static final UUID COURIER = UUID.randomUUID();
    private static final UUID ORDER = UUID.randomUUID();
    private static final UUID SLICE = UUID.randomUUID();
    private static final UUID PIZZA = UUID.randomUUID();
    private static final UUID DRINK = UUID.randomUUID();

    private DisputeRepository disputes;
    private OrderRepository orders;
    private OrderPayments payments;
    private ApplicationEventPublisher events;
    private DisputeService service;
    private CustomerOrder order;
    private SubOrder slice;

    @BeforeEach
    void setUp() {
        disputes = mock(DisputeRepository.class);
        orders = mock(OrderRepository.class);
        MerchantRepository merchants = mock(MerchantRepository.class);
        payments = mock(OrderPayments.class);
        events = mock(ApplicationEventPublisher.class);

        service = new DisputeService(disputes, orders, merchants, payments,
            new DeliveryPolicy(new StubConfig()), mock(MediaDocumentApi.class), events);

        Merchant forno = new Merchant(UUID.randomUUID(), "Forno Nero", "Pizza", null, 33.57, -7.58);
        set(forno, "id", MERCHANT);
        when(merchants.findById(MERCHANT)).thenReturn(Optional.of(forno));

        order = new CustomerOrder(CUSTOMER, "USD", "", OffsetDateTime.now());
        set(order, "id", ORDER);
        slice = order.addSubOrder(MERCHANT, 3_000, 300, 0, null, "");
        set(slice, "id", SLICE);
        order.addLine(slice, PIZZA, "Margherita", 2_000, 1);
        order.addLine(slice, DRINK, "Lemonade", 500, 2);
        order.priceIt(Basket.of(MERCHANT, 3_000, 300, 99, 0, 250, "USD"));
        order.assignCourier(UUID.randomUUID(), COURIER, "Yassine B.", "Bike",
            java.math.BigDecimal.valueOf(4.9), 210);
        order.held(OffsetDateTime.now());
        order.moveTo(OrderStatus.DELIVERED, OffsetDateTime.now());

        when(orders.findById(ORDER)).thenReturn(Optional.of(order));
        when(disputes.save(any())).thenAnswer(returnsFirstArg());
        when(payments.receivedOnOrder(any(), eq(DisputePayer.MERCHANT), any())).thenReturn(2_400L);
        when(payments.receivedOnOrder(any(), eq(DisputePayer.COURIER), any())).thenReturn(550L);
        when(payments.receivedOnOrder(any(), eq(DisputePayer.PLATFORM), any())).thenReturn(699L);
        when(payments.availableForPayer(any(), any(), any())).thenReturn(Long.MAX_VALUE);
    }

    // MARK: Filing one

    @Test
    @DisplayName("the claim is priced from the order's own lines, never from the request")
    void theClaimIsPricedServerSide() {
        DisputeDto filed = service.file(CUSTOMER, ORDER, request(DRINK, 2));

        // Two lemonades at 500, and the client never got to say what that was
        // worth — the same rule checkout follows.
        assertThat(filed.claimedCents()).isEqualTo(1_000);
        assertThat(filed.items()).singleElement()
            .extracting(DisputedItemDto::name).isEqualTo("Lemonade");
        assertThat(filed.state()).isEqualTo("OPEN");
    }

    /** Somebody reporting three missing drinks on an order of two has made a
     *  mistake worth correcting, not a request worth failing. */
    @Test
    void aQuantityAboveWhatWasOrderedIsClamped() {
        DisputeDto filed = service.file(CUSTOMER, ORDER, request(DRINK, 9));

        assertThat(filed.items()).singleElement()
            .extracting(DisputedItemDto::qty).isEqualTo(2);
        assertThat(filed.claimedCents()).isEqualTo(1_000);
    }

    @Test
    void anItemThatIsNotOnTheOrderIsDropped() {
        DisputeDto filed = service.file(CUSTOMER, ORDER, request(UUID.randomUUID(), 1));

        assertThat(filed.items()).isEmpty();
        assertThat(filed.claimedCents()).isZero();
    }

    @Test
    @DisplayName("an order that hasn't arrived has nothing to report yet")
    void anUndeliveredOrderIsRefused() {
        order.moveTo(OrderStatus.DELIVERING, OffsetDateTime.now());

        assertThatThrownBy(() -> service.file(CUSTOMER, ORDER, request(DRINK, 1)))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("once your order has arrived");
    }

    @Test
    void aCancelledOrderSaysSoRatherThanTakingAComplaint() {
        order.moveTo(OrderStatus.CANCELLED, OffsetDateTime.now());

        assertThatThrownBy(() -> service.file(CUSTOMER, ORDER, request(DRINK, 1)))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("nothing was charged");
    }

    /** Counted from delivery, not placement — which is what makes a scheduled
     *  order placed on Monday for Friday reportable at all. */
    @Test
    @DisplayName("the window is counted from delivery and closes")
    void anOldOrderIsOutsideTheWindow() {
        order.moveTo(OrderStatus.DELIVERED, OffsetDateTime.now().minusHours(30));

        assertThatThrownBy(() -> service.file(CUSTOMER, ORDER, request(DRINK, 1)))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("too old");
    }

    /** Not tidiness: two open reports on one order is two operators refunding
     *  the same missing pizza. */
    @Test
    void aSecondReportOnTheSameOrderIsRefused() {
        when(disputes.existsByOrderId(ORDER)).thenReturn(true);

        assertThatThrownBy(() -> service.file(CUSTOMER, ORDER, request(DRINK, 1)))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("already reported");
    }

    @Test
    void somebodyElsesOrderIsA404RatherThanA403() {
        assertThatThrownBy(() -> service.file(SOMEONE_ELSE, ORDER, request(DRINK, 1)))
            .isInstanceOf(ResponseStatusException.class)
            .extracting(e -> ((ResponseStatusException) e).getStatusCode())
            .isEqualTo(HttpStatus.NOT_FOUND);
    }

    // MARK: Resolving one — the refusals

    @Test
    @DisplayName("a refund over what that party was paid is refused, and names the figure")
    void aRefundCannotExceedWhatThePayerReceived() {
        Dispute dispute = open();

        assertThatThrownBy(() -> service.refund(dispute.getId(), 3_000, "MERCHANT", "", "admin"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("restaurant was paid")
            .hasMessageContaining("24.00");

        verify(payments, never()).refundDispute(any(), any(), any(), any(), anyInt());
    }

    /**
     * The interesting refusal. A kitchen that has already withdrawn cannot fund
     * this at all — merchant accounts cannot go negative — and the honest answer
     * is to say so and let a person decide who absorbs it, rather than quietly
     * moving the cost to the platform.
     */
    @Test
    @DisplayName("a payer who has already withdrawn is refused, not silently swapped")
    void aPayerWhoCannotCoverItIsRefused() {
        Dispute dispute = open();
        when(payments.availableForPayer(any(), eq(DisputePayer.MERCHANT), any()))
            .thenReturn(300L);

        assertThatThrownBy(() -> service.refund(dispute.getId(), 1_000, "MERCHANT", "", "admin"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("only has 3.00 left")
            .hasMessageContaining("take it from the platform");

        verify(payments, never()).refundDispute(any(), any(), any(), any(), anyInt());
    }

    @Test
    @DisplayName("an order cannot give back more than it took, across every refund on it")
    void refundsAreCappedByWhatTheCustomerPaid() {
        Dispute dispute = open();
        when(disputes.refundedOnOrder(ORDER)).thenReturn(order.getTotalCents() - 100);

        assertThatThrownBy(() -> service.refund(dispute.getId(), 500, "PLATFORM", "", "admin"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("more than the customer paid")
            .hasMessageContaining("1.00 left");
    }

    /** "The merchant pays" is not an instruction on an order spanning three of
     *  them, so it is refused rather than guessed at. */
    @Test
    void aMerchantRefundNeedsAKitchenNamed() {
        Dispute dispute = open(null);

        assertThatThrownBy(() -> service.refund(dispute.getId(), 500, "MERCHANT", "", "admin"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("isn't about one restaurant");
    }

    @Test
    void thereIsNoCourierToChargeOnACollection() {
        order.fulfilBy(FulfilmentKind.PICKUP);
        Dispute dispute = open();

        assertThatThrownBy(() -> service.refund(dispute.getId(), 300, "COURIER", "", "admin"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("collected it");
    }

    @Test
    @DisplayName("a refund of nothing is a rejection, and says so")
    void aZeroRefundIsRefused() {
        Dispute dispute = open();

        assertThatThrownBy(() -> service.refund(dispute.getId(), 0, "PLATFORM", "", "admin"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("reject it instead");
    }

    @Test
    void anAlreadyResolvedReportCannotBeResolvedAgain() {
        Dispute dispute = open();
        service.reject(dispute.getId(), "Everything was in the bag", "admin");

        assertThatThrownBy(() -> service.refund(dispute.getId(), 500, "PLATFORM", "", "admin"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("already been resolved");
    }

    // MARK: Resolving one — the money

    @Test
    @DisplayName("a refund within the cap moves the money and records who decided")
    void aRefundResolvesAndPays() {
        Dispute dispute = open();

        AdminDisputeDto resolved = service.refund(dispute.getId(), 1_000, "MERCHANT",
            "Two drinks missing", "admin@example.com");

        verify(payments).refundDispute(eq(order), eq(dispute.getId()),
            eq(DisputePayer.MERCHANT), eq(slice), eq(1_000));
        assertThat(resolved.dispute().state()).isEqualTo("RESOLVED_REFUND");
        assertThat(resolved.dispute().refundCents()).isEqualTo(1_000);
        assertThat(resolved.resolvedBy()).isEqualTo("admin@example.com");
    }

    /** The reason suggests a payer; it never decides one. An operator who sends
     *  no payer gets the suggestion, and can always override it. */
    @Test
    void theReasonOnlySuggestsWhoPays() {
        Dispute dispute = open(SLICE, DisputeReason.NEVER_ARRIVED);

        service.refund(dispute.getId(), 500, null, "", "admin");

        verify(payments).refundDispute(any(), any(), eq(DisputePayer.COURIER), any(), eq(500));
    }

    @Test
    @DisplayName("a rejection is an answer, and the customer hears about it")
    void aRejectionIsPushedTooAndCarriesItsReason() {
        Dispute dispute = open();

        AdminDisputeDto resolved = service.reject(dispute.getId(),
            "The photo shows the full order", "admin");

        assertThat(resolved.dispute().state()).isEqualTo("RESOLVED_REJECTED");
        assertThat(resolved.dispute().resolutionNote()).isEqualTo("The photo shows the full order");
        assertThat(resolved.dispute().refundCents()).isZero();
        verify(events).publishEvent(any(com.gojogo.delivery.OrderStatusChanged.class));
        verify(payments, never()).refundDispute(any(), any(), any(), any(), anyInt());
    }

    // MARK: Helpers

    private Dispute open() {
        return open(SLICE, DisputeReason.MISSING_ITEMS);
    }

    private Dispute open(UUID subOrderId) {
        return open(subOrderId, DisputeReason.MISSING_ITEMS);
    }

    private Dispute open(UUID subOrderId, DisputeReason reason) {
        Dispute dispute = new Dispute(order, subOrderId, reason, "Two drinks missing");
        set(dispute, "id", UUID.randomUUID());
        when(disputes.findById(dispute.getId())).thenReturn(Optional.of(dispute));
        return dispute;
    }

    private static FileDisputeRequest request(UUID itemId, int qty) {
        return new FileDisputeRequest(SLICE, "MISSING_ITEMS", "Two drinks missing",
            List.of(new DisputedItemRequest(itemId, qty)));
    }

    private static void set(Object target, String field, Object value) {
        try {
            Field f = target.getClass().getDeclaredField(field);
            f.setAccessible(true);
            f.set(target, value);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }

    private static final class StubConfig implements com.gojogo.config.ConfigApi {

        @Override
        public String string(String key, String fallback) {
            return fallback;
        }

        @Override
        public long number(String key, long fallback) {
            return fallback;
        }

        @Override
        public boolean flag(String key, boolean fallback) {
            return fallback;
        }
    }
}
