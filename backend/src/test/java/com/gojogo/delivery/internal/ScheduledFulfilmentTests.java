package com.gojogo.delivery.internal;

import com.gojogo.delivery.OrderPlaced;
import com.gojogo.dispatch.DispatchApi;
import com.gojogo.media.MediaDocumentApi;
import com.gojogo.messaging.MessagingApi;
import com.gojogo.profile.ProfileApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.context.ApplicationEventPublisher;

import java.lang.reflect.Field;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * A scheduled order reaching its kitchens, and being cooked for the right
 * moment (Phase 4 M5).
 *
 * <p>Two things are being pinned here and they are the whole of what makes a
 * booking different from an ordinary order. The kitchens find out at promotion
 * rather than at checkout — with everything that follows: the accept clock, the
 * queue row, the push. And a kitchen's prep estimate answers "how long do I
 * need", not "when do I start", so an eight o'clock dinner accepted at six is
 * not ready at twenty past.
 */
class ScheduledFulfilmentTests {

    private static final UUID FORNO_OWNER = UUID.randomUUID();
    private static final UUID SUSHI_OWNER = UUID.randomUUID();
    private static final UUID CUSTOMER = UUID.randomUUID();
    private static final UUID FORNO = UUID.randomUUID();
    private static final UUID SUSHI = UUID.randomUUID();
    private static final UUID ORDER = UUID.randomUUID();
    private static final UUID FORNO_SLICE = UUID.randomUUID();
    private static final UUID SUSHI_SLICE = UUID.randomUUID();

    private OrderRepository orders;
    private SubOrderRepository subOrders;
    private MerchantRepository merchants;
    private OrderPayments payments;
    private ApplicationEventPublisher events;
    private OrderFulfilmentService service;
    private Merchant forno;
    private Merchant sushi;
    private CustomerOrder order;
    private SubOrder fornoSlice;
    private SubOrder sushiSlice;

    @BeforeEach
    void setUp() {
        orders = mock(OrderRepository.class);
        subOrders = mock(SubOrderRepository.class);
        merchants = mock(MerchantRepository.class);
        payments = mock(OrderPayments.class);
        events = mock(ApplicationEventPublisher.class);

        service = new OrderFulfilmentService(orders, subOrders, merchants, payments,
            new DeliveryPolicy(new StubConfig()), mock(DispatchApi.class), mock(ProfileApi.class),
            mock(MessagingApi.class), mock(MediaDocumentApi.class), events);

        forno = new Merchant(FORNO_OWNER, "Forno Nero", "Pizza", null, 33.57, -7.58);
        set(forno, "id", FORNO);
        sushi = new Merchant(SUSHI_OWNER, "Kaido Sushi", "Sushi", null, 33.59, -7.61);
        set(sushi, "id", SUSHI);
        // A merchant is created closed and opened by its owner, so both have to
        // be switched on here: promotion reads exactly that flag.
        forno.setActive(true);
        sushi.setActive(true);
        when(merchants.findFirstByOwnerId(FORNO_OWNER)).thenReturn(Optional.of(forno));
        when(merchants.findFirstByOwnerId(SUSHI_OWNER)).thenReturn(Optional.of(sushi));
        when(merchants.findById(FORNO)).thenReturn(Optional.of(forno));
        when(merchants.findById(SUSHI)).thenReturn(Optional.of(sushi));
        when(merchants.findAllById(any())).thenReturn(List.of(forno, sushi));
    }

    // MARK: Promotion

    @Test
    @DisplayName("promotion is the moment the kitchens are told, and nothing else moves")
    void promotionTellsTheKitchens() {
        book(OffsetDateTime.now().plusHours(4), false);

        service.promote(ORDER);

        assertThat(order.getQueuedAt()).isNotNull();
        // Still CONFIRMED: "waiting for the restaurant to answer" is what it
        // was before this ran and what it is after. The stamp is the whole
        // transition — no seventh status, for the fifth milestone running.
        assertThat(order.getStatus()).isEqualTo(OrderStatus.CONFIRMED);
        assertThat(placedEvents()).extracting(OrderPlaced::merchantId)
            .containsExactlyInAnyOrder(FORNO, SUSHI);
        // Each owner hears about their own slice's food and nothing about the
        // other kitchen's.
        assertThat(placedEvents()).filteredOn(e -> e.merchantId().equals(SUSHI))
            .singleElement().extracting(OrderPlaced::totalCents).isEqualTo(3_000L);
    }

    @Test
    @DisplayName("promoting twice tells nobody twice")
    void promotionIsIdempotent() {
        book(OffsetDateTime.now().plusHours(4), false);

        service.promote(ORDER);
        service.promote(ORDER);

        assertThat(placedEvents()).hasSize(2);
    }

    /**
     * A restaurant that closed in the meantime is the one thing about a
     * scheduled order that can have changed since it was placed. Cancelled here
     * rather than left to the accept timeout: ten minutes of a customer waiting
     * to find out that a kitchen which shut on Tuesday is not going to answer is
     * ten minutes nobody needed to spend.
     */
    @Test
    void aKitchenThatHasClosedSinceIsCancelledAtPromotion() {
        book(OffsetDateTime.now().plusHours(4), false);
        forno.setActive(false);

        service.promote(ORDER);

        assertThat(fornoSlice.getStatus()).isEqualTo(SubOrderStatus.CANCELLED);
        assertThat(fornoSlice.getCancelReason()).contains("Forno Nero");
        verify(payments).releaseSubOrder(order, fornoSlice, "Forno Nero");
        // The order carries on with whoever is open, and only they are told.
        assertThat(order.getStatus()).isEqualTo(OrderStatus.CONFIRMED);
        assertThat(placedEvents()).extracting(OrderPlaced::merchantId).containsExactly(SUSHI);
    }

    @Test
    @DisplayName("every kitchen closed ends the order rather than announcing it to nobody")
    void allClosedEndsTheOrder() {
        book(OffsetDateTime.now().plusHours(4), false);
        forno.setActive(false);
        sushi.setActive(false);

        service.promote(ORDER);

        assertThat(order.getStatus()).isEqualTo(OrderStatus.CANCELLED);
        verify(payments).release(order);
        assertThat(placedEvents()).isEmpty();
    }

    @Test
    void aCancelledBookingIsNeverPromoted() {
        book(OffsetDateTime.now().plusHours(4), false);
        service.cancel(order, "You cancelled this order");

        service.promote(ORDER);

        assertThat(order.getQueuedAt()).isNull();
        assertThat(placedEvents()).isEmpty();
    }

    // MARK: Cooking for the right moment

    /**
     * The estimate says how long they need; it does not say when they start.
     * Without this a kitchen accepting at six with a twenty-minute estimate
     * would have an eight o'clock dinner cooked by twenty past — which is not
     * an early delivery, it is a cold one.
     */
    @Test
    @DisplayName("a kitchen's prep estimate does not pull a booking forward")
    void readinessIsAnchoredToTheBooking() {
        OffsetDateTime when = OffsetDateTime.now().plusHours(3);
        book(when, false);
        service.promote(ORDER);

        service.accept(FORNO_OWNER, FORNO_SLICE, 20);

        // Ready fifteen minutes (the configured dropoff) before it is wanted at
        // the door, not twenty minutes from now.
        assertNear(fornoSlice.getReadyAt(), when.minusMinutes(15));
        assertNear(order.getEtaAt(), when);
    }

    /** A collection is wanted on the counter at the moment the customer walks
     *  in — there is no journey to back off. */
    @Test
    void aScheduledCollectionIsReadyWhenTheCustomerArrives() {
        OffsetDateTime when = OffsetDateTime.now().plusHours(3);
        book(when, true);
        service.promote(ORDER);

        service.accept(FORNO_OWNER, FORNO_SLICE, 20);

        assertNear(fornoSlice.getReadyAt(), when);
    }

    /**
     * The honest half of the anchor. A kitchen that needs longer than there is
     * says so and the customer's countdown moves with it — clamping to the
     * promised time would be the system promising on the kitchen's behalf.
     */
    @Test
    @DisplayName("a kitchen that needs longer than there is slips the promise rather than hiding it")
    void aLateKitchenSlipsTheEta() {
        OffsetDateTime when = OffsetDateTime.now().plusMinutes(20);
        book(when, false);
        service.promote(ORDER);

        service.accept(FORNO_OWNER, FORNO_SLICE, 40);

        assertNear(fornoSlice.getReadyAt(), OffsetDateTime.now().plusMinutes(40));
        assertNear(order.getEtaAt(), OffsetDateTime.now().plusMinutes(55));
    }

    /** An ordinary order is untouched by any of this, which is the wire and
     *  behaviour compatibility claim stated as a test. */
    @Test
    void anOrdinaryOrderIsStillReadyWhenTheKitchenSaysSo() {
        book(null, false);

        service.accept(FORNO_OWNER, FORNO_SLICE, 20);

        assertNear(fornoSlice.getReadyAt(), OffsetDateTime.now().plusMinutes(20));
    }

    // MARK: Helpers

    /** An order for two kitchens, booked for {@code when} (or ordinary when
     *  null) and not yet in front of anybody. */
    private void book(OffsetDateTime when, boolean pickup) {
        order = new CustomerOrder(CUSTOMER, "USD", "",
            when == null ? OffsetDateTime.now().plusMinutes(40) : when);
        set(order, "id", ORDER);
        order.deliverTo(null, "Home", "12 Rue Ali", "", 33.58, -7.60);
        if (pickup) order.fulfilBy(FulfilmentKind.PICKUP);
        fornoSlice = order.addSubOrder(FORNO, 2_000, 300, 0, null, "");
        set(fornoSlice, "id", FORNO_SLICE);
        sushiSlice = order.addSubOrder(SUSHI, 3_000, 400, 0, null, "");
        set(sushiSlice, "id", SUSHI_SLICE);
        order.priceIt(Basket.of(List.of(
                Basket.MerchantSlice.of(FORNO, 2_000, 300, 0, null, "", ""),
                Basket.MerchantSlice.of(SUSHI, 3_000, 400, 0, null, "", "")),
            99, 0, "USD"));
        if (when == null) {
            order.queued(OffsetDateTime.now());
        } else {
            order.scheduleFor(when, when.minusMinutes(60));
        }
        when(orders.findById(ORDER)).thenReturn(Optional.of(order));
        when(subOrders.findById(FORNO_SLICE)).thenReturn(Optional.of(fornoSlice));
        when(subOrders.findById(SUSHI_SLICE)).thenReturn(Optional.of(sushiSlice));
    }

    private List<OrderPlaced> placedEvents() {
        ArgumentCaptor<Object> published = ArgumentCaptor.forClass(Object.class);
        verify(events, org.mockito.Mockito.atLeast(0)).publishEvent(published.capture());
        return published.getAllValues().stream()
            .filter(OrderPlaced.class::isInstance)
            .map(OrderPlaced.class::cast)
            .toList();
    }

    /** Times computed from {@code now()} inside the service and again here are
     *  seconds apart by construction. */
    private static void assertNear(OffsetDateTime actual, OffsetDateTime expected) {
        assertThat(Duration.between(expected, actual).abs())
            .isLessThan(Duration.ofSeconds(30));
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
