package com.gojogo.delivery.internal;

import com.gojogo.delivery.OrderStatusChanged;
import com.gojogo.dispatch.DispatchApi;
import com.gojogo.media.MediaDocumentApi;
import com.gojogo.messaging.MessagingApi;
import com.gojogo.profile.ProfileApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
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
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The kitchen's half of a collection (Phase 4 M4): no courier is looked for, the
 * code inverts, and the counter that hands the food over is the one that
 * finishes the order and gets paid.
 *
 * <p>The cases worth having are the ones where a pickup and a delivery diverge —
 * everything else is M1–M3's machinery working unchanged, which is the point of
 * this having been built as a kind rather than as a special case.
 */
class PickupCollectionTests {

    private static final UUID OWNER = UUID.randomUUID();
    private static final UUID SECOND_OWNER = UUID.randomUUID();
    private static final UUID CUSTOMER = UUID.randomUUID();
    private static final UUID FORNO = UUID.randomUUID();
    private static final UUID SUSHI = UUID.randomUUID();
    private static final UUID ORDER = UUID.randomUUID();
    private static final UUID FORNO_SLICE = UUID.randomUUID();
    private static final UUID SUSHI_SLICE = UUID.randomUUID();

    private OrderRepository orders;
    private SubOrderRepository subOrders;
    private OrderPayments payments;
    private DispatchApi dispatch;
    private ApplicationEventPublisher events;
    private OrderFulfilmentService service;
    private CustomerOrder order;
    private SubOrder fornoSlice;
    private SubOrder sushiSlice;

    @BeforeEach
    void setUp() {
        orders = mock(OrderRepository.class);
        subOrders = mock(SubOrderRepository.class);
        MerchantRepository merchants = mock(MerchantRepository.class);
        payments = mock(OrderPayments.class);
        dispatch = mock(DispatchApi.class);
        events = mock(ApplicationEventPublisher.class);

        service = new OrderFulfilmentService(orders, subOrders, merchants, payments,
            new DeliveryPolicy(new StubConfig()), dispatch, mock(ProfileApi.class),
            mock(MessagingApi.class), mock(MediaDocumentApi.class), events);

        Merchant forno = merchant(OWNER, FORNO, "Forno Nero");
        Merchant sushi = merchant(SECOND_OWNER, SUSHI, "Kaido Sushi");
        when(merchants.findFirstByOwnerId(OWNER)).thenReturn(Optional.of(forno));
        when(merchants.findFirstByOwnerId(SECOND_OWNER)).thenReturn(Optional.of(sushi));
        when(merchants.findById(FORNO)).thenReturn(Optional.of(forno));
        when(merchants.findById(SUSHI)).thenReturn(Optional.of(sushi));
        when(merchants.findAllById(any())).thenReturn(List.of(forno, sushi));

        order = new CustomerOrder(CUSTOMER, "USD", "", OffsetDateTime.now().plusMinutes(20));
        set(order, "id", ORDER);
        order.fulfilBy(FulfilmentKind.PICKUP);
        fornoSlice = order.addSubOrder(FORNO, 2_000, 0, 0, null, "");
        set(fornoSlice, "id", FORNO_SLICE);
        sushiSlice = order.addSubOrder(SUSHI, 3_000, 0, 0, null, "");
        set(sushiSlice, "id", SUSHI_SLICE);
        order.priceIt(Basket.of(List.of(
                Basket.MerchantSlice.of(FORNO, 2_000, 0, 0, null, "", ""),
                Basket.MerchantSlice.of(SUSHI, 3_000, 0, 0, null, "", "")),
            99, 0, "USD"));
        when(orders.findById(ORDER)).thenReturn(Optional.of(order));
        when(subOrders.findById(FORNO_SLICE)).thenReturn(Optional.of(fornoSlice));
        when(subOrders.findById(SUSHI_SLICE)).thenReturn(Optional.of(sushiSlice));
    }

    // MARK: Nobody is coming for it

    @Test
    @DisplayName("accepting a collection opens no courier search, ever")
    void noCourierIsLookedFor() {
        service.accept(OWNER, FORNO_SLICE, 10);
        service.accept(SECOND_OWNER, SUSHI_SLICE, 10);

        verify(dispatch, never()).request(any());
        assertThat(order.getCourierSearch()).isEqualTo(CourierSearch.NONE);
        assertThat(order.getStatus()).isEqualTo(OrderStatus.PREPARING);
    }

    /** The countdown is to the food being ready, with no journey added — a
     *  collection that promised fifteen more minutes would be counting down to
     *  a bag going cold on a counter. */
    @Test
    void theEtaIsReadinessAndNotReadinessPlusADrive() {
        service.accept(OWNER, FORNO_SLICE, 10);
        service.accept(SECOND_OWNER, SUSHI_SLICE, 25);

        assertThat(order.getReadyAt()).isEqualTo(sushiSlice.getReadyAt());
        assertThat(order.getEtaAt()).isEqualTo(order.getReadyAt());
    }

    /** No door, so no PIN. A number nobody will ever be asked for is a number
     *  sitting on a screen inviting somebody to read it out. */
    @Test
    void noDeliveryPinIsMinted() {
        service.accept(OWNER, FORNO_SLICE, 10);

        assertThat(order.getDeliveryPin()).isEmpty();
        assertThat(fornoSlice.getPickupCode()).hasSize(6);
    }

    // MARK: The code inverts

    @Test
    @DisplayName("the kitchen's own screen does not show the code it has to type")
    void theKitchenCannotReadTheCodeItTypes() {
        MerchantOrderDto accepted = service.accept(OWNER, FORNO_SLICE, 10);

        assertThat(accepted.fulfilmentKind()).isEqualTo("PICKUP");
        assertThat(accepted.pickupCode()).isEmpty();
        // …and it is a real code on the row, which the customer's own order is
        // what returns (see DeliveryService.collectionCode).
        assertThat(fornoSlice.getPickupCode()).isNotEmpty();
    }

    @Test
    void aDeliverySliceStillShowsItsCodeToTheKitchen() {
        order.fulfilBy(FulfilmentKind.DELIVERY);

        MerchantOrderDto accepted = service.accept(OWNER, FORNO_SLICE, 10);

        assertThat(accepted.pickupCode()).isEqualTo(fornoSlice.getPickupCode());
        assertThat(accepted.pickupCode()).isNotEmpty();
    }

    // MARK: Readiness is a fact, not an estimate

    @Test
    @DisplayName("marking ready pushes READY_FOR_PICKUP, once")
    void readyPushesOnceAndOnlyOnce() {
        service.accept(OWNER, FORNO_SLICE, 10);
        service.markReady(OWNER, FORNO_SLICE);
        service.markReady(OWNER, FORNO_SLICE);

        assertThat(fornoSlice.getReadyMarkedAt()).isNotNull();
        assertThat(pushedStatuses()).containsOnlyOnce("READY_FOR_PICKUP");
    }

    @Test
    void aDeliveryReadyPushesNothing() {
        order.fulfilBy(FulfilmentKind.DELIVERY);
        service.accept(OWNER, FORNO_SLICE, 10);
        service.markReady(OWNER, FORNO_SLICE);

        assertThat(pushedStatuses()).doesNotContain("READY_FOR_PICKUP");
    }

    // MARK: The handover

    @Test
    @DisplayName("a wrong code is a 200 that says so, and never counts")
    void aWrongCodeIsAnAnswer() {
        service.accept(OWNER, FORNO_SLICE, 10);

        CollectionResultDto result = service.collected(OWNER, FORNO_SLICE, "000000");

        assertThat(result.accepted()).isFalse();
        assertThat(result.message()).contains("doesn't match");
        assertThat(result.attemptsLeft()).isEqualTo(-1);
        assertThat(fornoSlice.getStatus()).isEqualTo(SubOrderStatus.PREPARING);
        // A refusal carries the slice back, so the screen the kitchen is
        // working from does not blank.
        assertThat(result.order()).isNotNull();
    }

    @Test
    void anEmptyCodeIsAlsoARefusalRatherThanAWayThrough() {
        service.accept(OWNER, FORNO_SLICE, 10);

        assertThat(service.collected(OWNER, FORNO_SLICE, null).accepted()).isFalse();
        assertThat(service.collected(OWNER, FORNO_SLICE, "").accepted()).isFalse();
        assertThat(fornoSlice.getStatus()).isEqualTo(SubOrderStatus.PREPARING);
    }

    /** One kitchen's digits must not open another's bag — the reason M3 put the
     *  code on the slice, tested from the other side of the counter. */
    @Test
    @DisplayName("one counter's code does not collect the other counter's bag")
    void aCodeOnlyOpensItsOwnCounter() {
        service.accept(OWNER, FORNO_SLICE, 10);
        service.accept(SECOND_OWNER, SUSHI_SLICE, 10);

        CollectionResultDto result =
            service.collected(OWNER, FORNO_SLICE, sushiSlice.getPickupCode());

        assertThat(result.accepted()).isFalse();
        assertThat(fornoSlice.getStatus()).isEqualTo(SubOrderStatus.PREPARING);
    }

    @Test
    @DisplayName("the last counter collected finishes the order and settles it")
    void theLastCounterFinishesTheOrder() {
        service.accept(OWNER, FORNO_SLICE, 10);
        service.accept(SECOND_OWNER, SUSHI_SLICE, 10);

        CollectionResultDto first =
            service.collected(OWNER, FORNO_SLICE, fornoSlice.getPickupCode());
        assertThat(first.accepted()).isTrue();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.PREPARING);
        verify(payments, never()).settle(any(), anyMap());

        CollectionResultDto last =
            service.collected(SECOND_OWNER, SUSHI_SLICE, sushiSlice.getPickupCode());

        assertThat(last.accepted()).isTrue();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.DELIVERED);
        assertThat(order.getSubOrders())
            .allMatch(s -> s.getStatus() == SubOrderStatus.DELIVERED);
        verify(payments).settle(any(), anyMap());
        // Dispatch was never asked for this order, so it is never told about it
        // either: completing a job that does not exist is a question with no
        // answer, not a harmless no-op.
        verify(dispatch, never()).complete(any(), any(), any());
        assertThat(pushedStatuses()).contains("DELIVERED");
    }

    /** A kitchen whose slice was cancelled must not hold the order open — the
     *  M3 rule, which a collection reaches by a different route. */
    @Test
    void aCancelledSliceDoesNotHoldTheOrderOpen() {
        service.accept(OWNER, FORNO_SLICE, 10);
        service.reject(SECOND_OWNER, SUSHI_SLICE, "Out of rice");

        service.collected(OWNER, FORNO_SLICE, fornoSlice.getPickupCode());

        assertThat(order.getStatus()).isEqualTo(OrderStatus.DELIVERED);
        assertThat(sushiSlice.getStatus()).isEqualTo(SubOrderStatus.CANCELLED);
    }

    // MARK: The verbs that belong to the other kind

    @Test
    @DisplayName("collect is refused on a delivery — that one is the courier's")
    void collectIsRefusedOnADelivery() {
        order.fulfilBy(FulfilmentKind.DELIVERY);
        service.accept(OWNER, FORNO_SLICE, 10);

        assertThatThrownBy(() -> service.collected(OWNER, FORNO_SLICE, "123456"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("the courier collects it")
            .extracting(e -> ((ResponseStatusException) e).getStatusCode())
            .isEqualTo(HttpStatus.CONFLICT);
    }

    @Test
    void collectIsRefusedBeforeTheKitchenHasAccepted() {
        assertThatThrownBy(() -> service.collected(OWNER, FORNO_SLICE, "123456"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Accept the order first");
    }

    @Test
    void collectingTwiceIsRefusedRatherThanSettlingTwice() {
        service.accept(OWNER, FORNO_SLICE, 10);
        service.accept(SECOND_OWNER, SUSHI_SLICE, 10);
        service.collected(OWNER, FORNO_SLICE, fornoSlice.getPickupCode());

        assertThatThrownBy(() ->
            service.collected(OWNER, FORNO_SLICE, fornoSlice.getPickupCode()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("already been collected");
    }

    // MARK: Helpers

    private List<String> pushedStatuses() {
        ArgumentCaptor<Object> captor = ArgumentCaptor.forClass(Object.class);
        verify(events, org.mockito.Mockito.atLeast(0)).publishEvent(captor.capture());
        return captor.getAllValues().stream()
            .filter(OrderStatusChanged.class::isInstance)
            .map(e -> ((OrderStatusChanged) e).status())
            .toList();
    }

    private static Merchant merchant(UUID ownerId, UUID id, String name) {
        Merchant merchant = new Merchant(ownerId, name, "Kitchen", null, 33.57, -7.58);
        set(merchant, "id", id);
        set(merchant, "pickupEnabled", true);
        return merchant;
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
