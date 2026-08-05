package com.gojogo.delivery.internal;

import com.gojogo.dispatch.DispatchApi;
import com.gojogo.media.MediaDocumentApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.lang.reflect.Field;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.AdditionalAnswers.returnsFirstArg;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Booking an order for later, and rewriting one before a kitchen has seen it
 * (Phase 4 M5).
 *
 * <p>The cases here are the ones that only exist because an order can now be
 * placed hours before anybody is asked about it: a kitchen that must not be
 * told yet, an order that must not occupy the live slot, a time that cannot be
 * made, and a basket that can still be rewritten because nothing has been
 * started.
 */
class ScheduledOrderTests {

    private static final UUID ME = UUID.randomUUID();
    private static final UUID FORNO = UUID.randomUUID();
    private static final UUID SUSHI = UUID.randomUUID();
    private static final UUID PIZZA_ITEM = UUID.randomUUID();
    private static final UUID ROLL_ITEM = UUID.randomUUID();
    private static final UUID ORDER = UUID.randomUUID();

    private MerchantRepository merchants;
    private OrderRepository orders;
    private PromotionService promotions;
    private OrderPayments payments;
    private OrderFulfilmentService fulfilment;
    private DeliveryService delivery;

    @BeforeEach
    void setUp() {
        merchants = mock(MerchantRepository.class);
        MenuItemRepository menuItems = mock(MenuItemRepository.class);
        orders = mock(OrderRepository.class);
        AddressRepository addresses = mock(AddressRepository.class);
        promotions = mock(PromotionService.class);
        payments = mock(OrderPayments.class);
        fulfilment = mock(OrderFulfilmentService.class);
        ApplicationEventPublisher events = mock(ApplicationEventPublisher.class);

        delivery = new DeliveryService(merchants, menuItems, orders, addresses, events,
            payments, promotions, mock(MerchantStorefrontService.class),
            fulfilment, mock(DispatchApi.class),
            new DeliveryPolicy(new StubConfig()), mock(MediaDocumentApi.class), mock(com.gojogo.share.ShareApi.class), 99);

        Merchant forno = merchant(FORNO, "Forno Nero", 300, 25);
        Merchant sushi = merchant(SUSHI, "Kaido Sushi", 400, 50);
        when(merchants.findById(FORNO)).thenReturn(Optional.of(forno));
        when(merchants.findById(SUSHI)).thenReturn(Optional.of(sushi));
        when(menuItems.findForMerchant(eq(FORNO), any()))
            .thenReturn(List.of(item(PIZZA_ITEM, "Margherita", 2_000)));
        when(menuItems.findForMerchant(eq(SUSHI), any()))
            .thenReturn(List.of(item(ROLL_ITEM, "Dragon roll", 3_000)));
        when(promotions.resolve(any(), any(), isNull(), anyInt(), anyInt(), anyBoolean()))
            .thenReturn(PromotionService.Applied.none());
        when(orders.save(any())).thenAnswer(returnsFirstArg());
        when(payments.currency()).thenReturn("USD");
    }

    // MARK: Placing one

    @Test
    @DisplayName("a scheduled order is placed, paid for, and told to nobody yet")
    void theKitchenIsNotToldUntilItIsTime() {
        OffsetDateTime when = OffsetDateTime.now().plusHours(6);

        OrderDto placed = delivery.place(ME, scheduled(when, basket(FORNO, PIZZA_ITEM, 1)));

        assertThat(placed.scheduledFor()).isEqualTo(when);
        assertThat(placed.queuedAt()).isNull();
        assertThat(placed.status()).isEqualTo(OrderStatus.CONFIRMED.name());
        // The money is held now, exactly as at any other checkout. Holding at
        // promotion instead would move the only moment this can fail to the one
        // moment nothing can be done about it.
        verify(payments).hold(any(), anyString());
        verify(fulfilment, never()).announce(any());
    }

    /** The ETA is the promise, not a courier's arithmetic over the ordinary
     *  advertised time — that is what the customer picked. */
    @Test
    void theEtaIsTheTimeTheyAskedFor() {
        OffsetDateTime when = OffsetDateTime.now().plusHours(4);

        OrderDto placed = delivery.place(ME, scheduled(when, basket(FORNO, PIZZA_ITEM, 1)));

        assertThat(placed.etaAt()).isEqualTo(when);
        assertThat(placed.changeable()).isTrue();
    }

    /**
     * The kitchens are told with enough notice to answer <em>and</em> to cook:
     * the slowest one's own advertised time plus the window they get to accept
     * in.
     */
    @Test
    @DisplayName("the promotion is backed off the slowest kitchen in the cart")
    void thePromotionIsTimedToTheSlowestKitchen() {
        OffsetDateTime when = OffsetDateTime.now().plusHours(8);

        delivery.place(ME, scheduled(when, basket(FORNO, PIZZA_ITEM, 1),
            basket(SUSHI, ROLL_ITEM, 1)));

        ArgumentCaptor<CustomerOrder> saved = ArgumentCaptor.forClass(CustomerOrder.class);
        verify(orders).save(saved.capture());
        // Sushi's 50 minutes, not Forno's 25, plus the ten-minute accept window.
        assertNear(saved.getValue().getQueueAt(),
            when.minusMinutes(60));
    }

    @Test
    @DisplayName("a time nobody could cook for is refused, and says how much notice it needs")
    void tooSoonIsRefused() {
        assertThatThrownBy(() -> delivery.place(ME,
            scheduled(OffsetDateTime.now().plusMinutes(20), basket(SUSHI, ROLL_ITEM, 1))))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("60 minutes");

        verify(payments, never()).hold(any(), anyString());
    }

    /**
     * The floor is config, but the real minimum is this basket's own — a
     * kitchen advertising fifty minutes cannot make an order booked in forty,
     * and a picker built on the configured forty-five would have offered it.
     */
    @Test
    void theMinimumIsTheBasketsAndNotTheConfiguredFloor() {
        OffsetDateTime justOverTheFloor = OffsetDateTime.now().plusMinutes(50);

        assertThatThrownBy(() -> delivery.place(ME,
            scheduled(justOverTheFloor, basket(SUSHI, ROLL_ITEM, 1))))
            .isInstanceOf(ResponseStatusException.class);

        // The same time is fine at the faster kitchen: 25 + 10 is 35 minutes,
        // so the configured 45-minute floor is what binds there.
        assertThat(delivery.place(ME, scheduled(justOverTheFloor, basket(FORNO, PIZZA_ITEM, 1)))
            .scheduledFor()).isEqualTo(justOverTheFloor);
    }

    @Test
    void tooFarAheadIsRefused() {
        assertThatThrownBy(() -> delivery.place(ME,
            scheduled(OffsetDateTime.now().plusDays(30), basket(FORNO, PIZZA_ITEM, 1))))
            .isInstanceOf(ResponseStatusException.class)
            .extracting(e -> ((ResponseStatusException) e).getStatusCode())
            .isEqualTo(HttpStatus.BAD_REQUEST);
    }

    // MARK: The live-order slot

    /**
     * Booking Thursday's lunch must not stop somebody eating tonight, and the
     * rule reads the other way too. The one-order-at-a-time rule is about
     * orders being fulfilled.
     */
    @Test
    @DisplayName("a booked order does not occupy the live slot")
    void aBookedOrderDoesNotBlockAnImmediateOne() {
        when(orders.liveFor(eq(ME), any())).thenReturn(List.of());
        when(orders.waitingFor(eq(ME), any())).thenReturn(List.of(mock(CustomerOrder.class)));

        assertThat(delivery.place(ME, immediate(basket(FORNO, PIZZA_ITEM, 1))))
            .isNotNull();
    }

    @Test
    void anOrderInFlightStillBlocksASecondImmediateOne() {
        when(orders.liveFor(eq(ME), any())).thenReturn(List.of(mock(CustomerOrder.class)));

        assertThatThrownBy(() -> delivery.place(ME, immediate(basket(FORNO, PIZZA_ITEM, 1))))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("already have an order");
    }

    @Test
    @DisplayName("an order in flight does not stop somebody booking for later")
    void anOrderInFlightDoesNotBlockABooking() {
        when(orders.liveFor(eq(ME), any())).thenReturn(List.of(mock(CustomerOrder.class)));

        assertThat(delivery.place(ME,
            scheduled(OffsetDateTime.now().plusHours(5), basket(FORNO, PIZZA_ITEM, 1))))
            .isNotNull();
    }

    @Test
    void thereIsACapOnHowManyCanBeWaiting() {
        when(orders.waitingFor(eq(ME), any())).thenReturn(List.of(
            mock(CustomerOrder.class), mock(CustomerOrder.class), mock(CustomerOrder.class),
            mock(CustomerOrder.class), mock(CustomerOrder.class)));

        assertThatThrownBy(() -> delivery.place(ME,
            scheduled(OffsetDateTime.now().plusHours(5), basket(FORNO, PIZZA_ITEM, 1))))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("cancel one");
    }

    // MARK: Opening hours (Phase 4 M6)

    /**
     * A kitchen that is shut is refused at checkout rather than ten minutes
     * later by the accept timeout — which is what used to happen, and what made
     * "closed" indistinguishable from "ignoring you".
     */
    @Test
    @DisplayName("an order for now is refused by a kitchen that is closed at this hour")
    void aClosedKitchenRefusesAnImmediateOrder() {
        closeForno();

        assertThatThrownBy(() -> delivery.place(ME, immediate(basket(FORNO, PIZZA_ITEM, 1))))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("closed right now");
    }

    /**
     * But a <em>booking</em> is not: a kitchen shut at lunchtime may be open at
     * eight, and refusing at checkout would make it impossible to book anything
     * outside opening hours — which is most of when people book. The clock is
     * read at promotion instead.
     */
    @Test
    @DisplayName("a booking is not refused by the hours at the moment it is made")
    void aClosedKitchenStillTakesABooking() {
        closeForno();

        assertThat(delivery.place(ME,
            scheduled(OffsetDateTime.now().plusHours(6), basket(FORNO, PIZZA_ITEM, 1))))
            .isNotNull();
    }

    /** A quote is somebody reading a menu. Refusing to price food at midnight
     *  would make the restaurant page useless rather than honest. */
    @Test
    void aQuoteStillPricesAClosedKitchen() {
        closeForno();

        assertThat(delivery.quote(ME, new QuoteRequest(null, null,
            List.of(basket(FORNO, PIZZA_ITEM, 1)), null, 0, null)).totalCents())
            .isEqualTo(2_000 + 300 + 99);
    }

    /** Open only in a one-minute window on a Monday morning, which no test run
     *  will ever fall inside. */
    private void closeForno() {
        Merchant closed = merchant(FORNO, "Forno Nero", 300, 25);
        closed.apply("Forno Nero", "Kitchen", null, null, 25, 300, 33.57, -7.58,
            Set.of(), Set.of(), false, null, "", "MON=03:00-03:01", "Africa/Casablanca");
        when(merchants.findById(FORNO)).thenReturn(Optional.of(closed));
    }

    // MARK: The quote's window

    /**
     * The picker's bounds come from the server because they are this basket's,
     * not a constant — the refusal above is the same rule, and a client that
     * had to guess would meet it after the customer had already chosen a time.
     */
    @Test
    void theQuoteCarriesTheWindowForThisBasket() {
        QuoteDto quote = delivery.quote(ME, new QuoteRequest(null, null,
            List.of(basket(SUSHI, ROLL_ITEM, 1)), null, 0, null));

        assertNear(quote.earliestScheduleAt(),
            OffsetDateTime.now().plusMinutes(60));
        assertNear(quote.latestScheduleAt(),
            OffsetDateTime.now().plusDays(7));
    }

    // MARK: Changing one

    @Test
    @DisplayName("a bigger basket moves the hold by the difference, not by a refund and a recharge")
    void changingRepricesAndAdjustsTheHold() {
        CustomerOrder booked = booked(OffsetDateTime.now().plusHours(6),
            basket(FORNO, PIZZA_ITEM, 1));
        int before = booked.getTotalCents();

        OrderDto changed = delivery.change(ME, ORDER, sameTime(booked,
            basket(FORNO, PIZZA_ITEM, 3)));

        assertThat(changed.subtotalCents()).isEqualTo(6_000);
        assertThat(changed.lines()).singleElement()
            .extracting(OrderLineDto::qty).isEqualTo(3);
        verify(payments).adjustHold(eq(booked), eq(before), anyString());
    }

    @Test
    @DisplayName("changing the time re-times the promotion with it")
    void changingTheTimeMovesThePromotion() {
        CustomerOrder booked = booked(OffsetDateTime.now().plusHours(6),
            basket(FORNO, PIZZA_ITEM, 1));
        OffsetDateTime later = OffsetDateTime.now().plusHours(9);

        delivery.change(ME, ORDER, scheduled(later, basket(FORNO, PIZZA_ITEM, 1)));

        assertThat(booked.getScheduledFor()).isEqualTo(later);
        assertNear(booked.getQueueAt(), later.minusMinutes(45));
        assertThat(booked.getRevision()).isEqualTo(1);
    }

    /**
     * The order's redemptions are released <em>before</em> it is re-priced,
     * and the ordering is the point rather than a detail.
     *
     * <p>Resolving a code counts what this customer has already redeemed, and
     * this order's own row is among them — so releasing afterwards would refuse
     * a once-per-customer code on the very order that is carrying it, telling
     * somebody they had already used a code they are holding. Whatever survives
     * is recorded again on the way out.
     */
    @Test
    @DisplayName("a change gives its own promotion back before re-pricing, not after")
    void redemptionsAreReleasedBeforeThePriceIsResolvedAgain() {
        UUID promo = UUID.randomUUID();
        PromotionService.Applied applied =
            new PromotionService.Applied(promo, "WELCOME10", "10% off", 400);
        when(promotions.resolve(eq(FORNO), any(), any(), anyInt(), anyInt(), anyBoolean()))
            .thenReturn(applied);
        CustomerOrder booked = booked(OffsetDateTime.now().plusHours(6),
            basket(FORNO, PIZZA_ITEM, 1));

        delivery.change(ME, ORDER, sameTime(booked, basket(FORNO, PIZZA_ITEM, 2)));

        InOrder order = inOrder(promotions);
        order.verify(promotions).keepOnlyRedemptions(ORDER, Set.of());
        order.verify(promotions).resolve(eq(FORNO), eq(ME), any(), eq(4_000), anyInt(),
            anyBoolean());
        order.verify(promotions).redeem(applied, ME, ORDER);
    }

    @Test
    @DisplayName("an order a kitchen already has cannot be changed")
    void anAnnouncedOrderIsNoLongerTheCustomersToRewrite() {
        CustomerOrder booked = booked(OffsetDateTime.now().plusHours(6),
            basket(FORNO, PIZZA_ITEM, 1));
        booked.queued(OffsetDateTime.now());

        assertThatThrownBy(() -> delivery.change(ME, ORDER,
            sameTime(booked, basket(FORNO, PIZZA_ITEM, 2))))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("cancel it");

        verify(payments, never()).adjustHold(any(), anyInt(), anyString());
    }

    /** An ordinary order is in front of a kitchen from the moment it is placed,
     *  so it has no editable window at all. */
    @Test
    void anImmediateOrderIsNeverChangeable() {
        CustomerOrder placed = placedNow(basket(FORNO, PIZZA_ITEM, 1));

        assertThat(placed.isChangeable()).isFalse();
        assertThatThrownBy(() -> delivery.change(ME, ORDER,
            immediate(basket(FORNO, PIZZA_ITEM, 2))))
            .isInstanceOf(ResponseStatusException.class);
    }

    // MARK: Helpers

    private CustomerOrder booked(OffsetDateTime when, BasketRequest... baskets) {
        return capture(delivery.place(ME, scheduled(when, baskets)));
    }

    private CustomerOrder placedNow(BasketRequest... baskets) {
        return capture(delivery.place(ME, immediate(baskets)));
    }

    /** The row {@code place} actually saved, given an id and made findable —
     *  which is what {@code change} needs and a mock repository does not do. */
    private CustomerOrder capture(OrderDto ignored) {
        ArgumentCaptor<CustomerOrder> saved = ArgumentCaptor.forClass(CustomerOrder.class);
        verify(orders).save(saved.capture());
        CustomerOrder order = saved.getValue();
        set(order, "id", ORDER);
        order.getSubOrders().forEach(sub -> set(sub, "id", UUID.randomUUID()));
        when(orders.findById(ORDER)).thenReturn(Optional.of(order));
        return order;
    }

    private static PlaceOrderRequest scheduled(OffsetDateTime when, BasketRequest... baskets) {
        return new PlaceOrderRequest(null, null, List.of(baskets), null, "Home", "",
            null, 0, null, null, null, null, when);
    }

    private static PlaceOrderRequest sameTime(CustomerOrder order, BasketRequest... baskets) {
        return scheduled(order.getScheduledFor(), baskets);
    }

    private static PlaceOrderRequest immediate(BasketRequest... baskets) {
        return new PlaceOrderRequest(null, null, List.of(baskets), null, "Home", "",
            null, 0, null, null, null, null, null);
    }

    private static BasketRequest basket(UUID merchantId, UUID itemId, int qty) {
        return new BasketRequest(merchantId, List.of(new OrderLineRequest(itemId, qty)), null);
    }

    /** Times computed from {@code now()} inside the service and again in the
     *  test are seconds apart by construction, so they are compared with a
     *  tolerance rather than for equality. */
    private static void assertNear(OffsetDateTime actual, OffsetDateTime expected) {
        assertThat(java.time.Duration.between(expected, actual).abs())
            .isLessThan(java.time.Duration.ofSeconds(30));
    }

    private static Merchant merchant(UUID id, String name, int deliveryFeeCents, int etaMinutes) {
        Merchant merchant = new Merchant(UUID.randomUUID(), name, "Kitchen", null, 33.57, -7.58);
        set(merchant, "id", id);
        // A restaurant is created closed and published by its owner. Checkout
        // reads that flag since Phase 4 M6, so an orderable one has to be open.
        merchant.setActive(true);
        set(merchant, "deliveryFeeCents", deliveryFeeCents);
        set(merchant, "etaMinutes", etaMinutes);
        return merchant;
    }

    private static MenuItem item(UUID id, String name, int priceCents) {
        MenuItem item = new MenuItem(UUID.randomUUID(), 0);
        item.apply(name, "", priceCents, null, false, true);
        set(item, "id", id);
        return item;
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
