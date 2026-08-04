package com.gojogo.delivery.internal;

import com.gojogo.delivery.OrderPlaced;
import com.gojogo.dispatch.DispatchApi;
import com.gojogo.media.MediaDocumentApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.lang.reflect.Field;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.AdditionalAnswers.returnsFirstArg;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * One checkout across kitchens (Phase 4 M3): the shape of the request, the cap
 * that keeps a single courier honest, and the arithmetic that has to survive a
 * slice being someone else's business.
 *
 * <p>Every money case here feeds the same invariant the single-merchant order
 * had — the splits at settlement plus what was released must equal the hold —
 * so what is being tested at checkout is that each slice's numbers are its own
 * merchant's and the order-level amounts are charged once.
 */
class MultiMerchantOrderTests {

    private static final UUID ME = UUID.randomUUID();
    private static final UUID FORNO = UUID.randomUUID();
    private static final UUID SUSHI = UUID.randomUUID();
    private static final UUID PIZZA_ITEM = UUID.randomUUID();
    private static final UUID ROLL_ITEM = UUID.randomUUID();

    private MerchantRepository merchants;
    private MenuItemRepository menuItems;
    private OrderRepository orders;
    private PromotionService promotions;
    private OrderPayments payments;
    private ApplicationEventPublisher events;
    private DeliveryService delivery;
    private OrderFulfilmentService fulfilment;

    @BeforeEach
    void setUp() {
        merchants = mock(MerchantRepository.class);
        menuItems = mock(MenuItemRepository.class);
        orders = mock(OrderRepository.class);
        promotions = mock(PromotionService.class);
        payments = mock(OrderPayments.class);
        events = mock(ApplicationEventPublisher.class);
        fulfilment = mock(OrderFulfilmentService.class);

        delivery = new DeliveryService(merchants, menuItems, orders,
            mock(AddressRepository.class), events, payments, promotions,
            mock(MerchantStorefrontService.class), fulfilment, mock(DispatchApi.class),
            new DeliveryPolicy(new StubConfig()), mock(MediaDocumentApi.class), 99);

        Merchant forno = merchant(FORNO, "Forno Nero", 300, 25);
        Merchant sushi = merchant(SUSHI, "Kaido Sushi", 400, 40);
        when(merchants.findById(FORNO)).thenReturn(Optional.of(forno));
        when(merchants.findById(SUSHI)).thenReturn(Optional.of(sushi));

        MenuItem pizza = item(PIZZA_ITEM, forno, "Margherita", 2_000);
        MenuItem roll = item(ROLL_ITEM, sushi, "Dragon roll", 3_000);
        when(menuItems.findForMerchant(eq(FORNO), any())).thenReturn(List.of(pizza));
        when(menuItems.findForMerchant(eq(SUSHI), any())).thenReturn(List.of(roll));

        when(promotions.resolve(any(), any(), isNull(), anyInt(), anyInt(), anyBoolean()))
            .thenReturn(PromotionService.Applied.none());
        when(orders.save(any())).thenAnswer(returnsFirstArg());
        when(payments.currency()).thenReturn("USD");
    }

    // MARK: The shape of the request

    @Test
    @DisplayName("two baskets become one order with a slice per kitchen")
    void twoBasketsOneOrder() {
        OrderDto placed = delivery.place(ME, request(basket(FORNO, PIZZA_ITEM, 2),
            basket(SUSHI, ROLL_ITEM, 1)));

        assertThat(placed.subOrders()).hasSize(2);
        assertThat(placed.subtotalCents()).isEqualTo(7_000);          // 2×2000 + 3000
        assertThat(placed.deliveryFeeCents()).isEqualTo(700);         // 300 + 400
        assertThat(placed.serviceFeeCents()).isEqualTo(99);           // once, not per kitchen
        assertThat(placed.totalCents()).isEqualTo(7_000 + 700 + 99);
        assertThat(placed.subOrders())
            .extracting(SubOrderDto::merchantId)
            .containsExactly(FORNO, SUSHI);
        // Each slice carries its own merchant's numbers, because each is what
        // a cancellation of that slice alone gives back.
        assertThat(placed.subOrders().getFirst().subtotalCents()).isEqualTo(4_000);
        assertThat(placed.subOrders().getFirst().deliveryFeeCents()).isEqualTo(300);
        assertThat(placed.subOrders().getLast().subtotalCents()).isEqualTo(3_000);
        assertThat(placed.subOrders().getLast().deliveryFeeCents()).isEqualTo(400);
    }

    /** The deployed app sends merchantId + lines and nothing else. It must keep
     *  working, as a one-basket order. */
    @Test
    void theLegacySingleMerchantShapeStillPlaces() {
        OrderDto placed = delivery.place(ME, new PlaceOrderRequest(FORNO,
            List.of(new OrderLineRequest(PIZZA_ITEM, 1)), null, null, "Home", "", null, 0, null, null, null));

        assertThat(placed.subOrders()).hasSize(1);
        assertThat(placed.totalCents()).isEqualTo(2_000 + 300 + 99);
    }

    /** One courier collects every bag; the cap is what keeps not building the
     *  multi-courier split honest. */
    @Test
    @DisplayName("an order across more than CONFIG 3 kitchens is refused")
    void theMerchantCapIsEnforced() {
        BasketRequest[] four = new BasketRequest[4];
        for (int i = 0; i < 4; i++) {
            UUID merchantId = i == 0 ? FORNO : UUID.randomUUID();
            when(merchants.findById(merchantId))
                .thenReturn(Optional.of(merchant(merchantId, "Kitchen " + i, 300, 20)));
            four[i] = basket(merchantId, PIZZA_ITEM, 1);
        }

        assertThatThrownBy(() -> delivery.place(ME, request(four)))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("at most 3");
    }

    @Test
    void twoBasketsForTheSameKitchenAreRefusedRatherThanMerged() {
        assertThatThrownBy(() -> delivery.place(ME,
            request(basket(FORNO, PIZZA_ITEM, 1), basket(FORNO, PIZZA_ITEM, 1))))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("One basket per restaurant");
    }

    @Test
    void aRequestWithNeitherShapeIsA400() {
        assertThatThrownBy(() -> delivery.place(ME, new PlaceOrderRequest(null, null, null,
            null, "Home", "", null, 0, null, null, null)))
            .isInstanceOf(ResponseStatusException.class)
            .extracting(e -> ((ResponseStatusException) e).getStatusCode())
            .isEqualTo(HttpStatus.BAD_REQUEST);
    }

    // MARK: Who is told

    /**
     * An ordinary order announces itself the moment it is placed, with every
     * kitchen on it.
     *
     * <p>The announcement itself moved into {@code OrderFulfilmentService} in
     * Phase 4 M5, so that an order placed now and a scheduled one promoted at
     * seven o'clock tell their kitchens through the same code — what is checked
     * here is that placement still triggers it, and what each kitchen is told
     * is checked where it is now built ({@code ScheduledOrderTests}).
     */
    @Test
    void placingAnnouncesToTheKitchensImmediately() {
        delivery.place(ME, request(basket(FORNO, PIZZA_ITEM, 2), basket(SUSHI, ROLL_ITEM, 1)));

        ArgumentCaptor<CustomerOrder> announced = ArgumentCaptor.forClass(CustomerOrder.class);
        org.mockito.Mockito.verify(fulfilment).announce(announced.capture());
        assertThat(announced.getValue().getSubOrders()).extracting(SubOrder::getMerchantId)
            .containsExactlyInAnyOrder(FORNO, SUSHI);
        // In front of them from this moment, which is the fact the kitchen's
        // queue and the accept timeout are both read off.
        assertThat(announced.getValue().getQueuedAt()).isNotNull();
    }

    // MARK: A shared promotion code

    /**
     * The customer has one code field, so the top-level code is tried against
     * every basket and applied where it lands — a code that is one merchant's
     * campaign must not discount another merchant's food.
     */
    @Test
    @DisplayName("a shared code lands on the kitchen it belongs to and nowhere else")
    void aSharedCodeLandsWhereItResolves() {
        when(promotions.resolve(eq(FORNO), any(), eq("WELCOME10"), anyInt(), anyInt(), anyBoolean()))
            .thenThrow(new ResponseStatusException(HttpStatus.NOT_FOUND,
                "That code isn't valid here"));
        UUID promo = UUID.randomUUID();
        when(promotions.resolve(eq(SUSHI), any(), eq("WELCOME10"), anyInt(), anyInt(), anyBoolean()))
            .thenReturn(new PromotionService.Applied(promo, "WELCOME10", "10% off", 300));

        QuoteDto quote = delivery.quote(ME, new QuoteRequest(null, null,
            List.of(basket(FORNO, PIZZA_ITEM, 1), basket(SUSHI, ROLL_ITEM, 1)),
            "WELCOME10", 0, null));

        assertThat(quote.discountCents()).isEqualTo(300);
        assertThat(quote.merchants())
            .filteredOn(m -> m.merchantId().equals(FORNO))
            .singleElement()
            .extracting(MerchantQuoteDto::discountCents)
            .isEqualTo(0);
        assertThat(quote.merchants())
            .filteredOn(m -> m.merchantId().equals(SUSHI))
            .singleElement()
            .extracting(MerchantQuoteDto::promotionCode)
            .isEqualTo("WELCOME10");
    }

    /** Somebody who typed WELCOME10 and got nothing anywhere deserves to be
     *  told why — silence would look like a discount that never arrived. */
    @Test
    void aCodeThatLandsNowhereIsRefusedOutLoud() {
        when(promotions.resolve(any(), any(), eq("NOPE"), anyInt(), anyInt(), anyBoolean()))
            .thenThrow(new ResponseStatusException(HttpStatus.NOT_FOUND,
                "That code isn't valid here"));

        assertThatThrownBy(() -> delivery.quote(ME, new QuoteRequest(null, null,
            List.of(basket(FORNO, PIZZA_ITEM, 1), basket(SUSHI, ROLL_ITEM, 1)), "NOPE", 0,
            null)))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("isn't valid here");
    }

    // MARK: Cancelling one kitchen

    /** SPECS §5's rule, on the customer's side: a slice is theirs to cancel
     *  exactly until its kitchen says yes. */
    @Test
    void aSliceCanBeCancelledOnlyUntilItsKitchenAccepts() {
        delivery.place(ME, request(basket(FORNO, PIZZA_ITEM, 2), basket(SUSHI, ROLL_ITEM, 1)));
        CustomerOrder order = savedOrder();
        UUID orderId = UUID.randomUUID();
        set(order, "id", orderId);
        when(orders.findById(orderId)).thenReturn(Optional.of(order));
        SubOrder sushiSlice = order.getSubOrders().getLast();
        UUID sliceId = UUID.randomUUID();
        set(sushiSlice, "id", sliceId);
        sushiSlice.accepted(java.time.OffsetDateTime.now(), 20, null);

        assertThatThrownBy(() -> delivery.cancelSubOrder(ME, orderId, sliceId))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("already cooking");
    }

    // MARK: Helpers

    private PlaceOrderRequest request(BasketRequest... baskets) {
        return new PlaceOrderRequest(null, null, List.of(baskets), null, "Home", "",
            null, 0, null, null, null);
    }

    private static BasketRequest basket(UUID merchantId, UUID itemId, int qty) {
        return new BasketRequest(merchantId, List.of(new OrderLineRequest(itemId, qty)), null);
    }

    private CustomerOrder savedOrder() {
        ArgumentCaptor<CustomerOrder> captor = ArgumentCaptor.forClass(CustomerOrder.class);
        org.mockito.Mockito.verify(orders).save(captor.capture());
        return captor.getValue();
    }

    private static Merchant merchant(UUID id, String name, int deliveryFeeCents, int etaMinutes) {
        Merchant merchant = new Merchant(UUID.randomUUID(), name, "Kitchen", null, 33.57, -7.58);
        set(merchant, "id", id);
        set(merchant, "deliveryFeeCents", deliveryFeeCents);
        set(merchant, "etaMinutes", etaMinutes);
        return merchant;
    }

    private static MenuItem item(UUID id, Merchant merchant, String name, int priceCents) {
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
