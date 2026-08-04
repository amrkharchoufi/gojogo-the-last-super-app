package com.gojogo.delivery.internal;

import com.gojogo.dispatch.DispatchApi;
import com.gojogo.media.MediaDocumentApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.lang.reflect.Field;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.AdditionalAnswers.returnsFirstArg;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Checking out a collection (Phase 4 M4).
 *
 * <p>The cases here are the ones that separate a pickup from "a delivery whose
 * courier happens to be nobody" — the modelling mistake this milestone exists
 * to avoid. No delivery fee, no tip, no address required, a merchant who does
 * not do collection refusing out loud, and a free-delivery promotion refused
 * rather than quietly becoming money off food.
 */
class PickupOrderTests {

    private static final UUID ME = UUID.randomUUID();
    private static final UUID FORNO = UUID.randomUUID();
    private static final UUID SUSHI = UUID.randomUUID();
    private static final UUID PIZZA_ITEM = UUID.randomUUID();
    private static final UUID ROLL_ITEM = UUID.randomUUID();

    private MerchantRepository merchants;
    private MenuItemRepository menuItems;
    private OrderRepository orders;
    private AddressRepository addresses;
    private PromotionService promotions;
    private OrderPayments payments;
    private DeliveryService delivery;

    @BeforeEach
    void setUp() {
        merchants = mock(MerchantRepository.class);
        menuItems = mock(MenuItemRepository.class);
        orders = mock(OrderRepository.class);
        addresses = mock(AddressRepository.class);
        promotions = mock(PromotionService.class);
        payments = mock(OrderPayments.class);
        ApplicationEventPublisher events = mock(ApplicationEventPublisher.class);

        delivery = new DeliveryService(merchants, menuItems, orders, addresses, events,
            payments, promotions, mock(MerchantStorefrontService.class),
            mock(OrderFulfilmentService.class), mock(DispatchApi.class),
            new DeliveryPolicy(new StubConfig()), mock(MediaDocumentApi.class), 99);

        Merchant forno = merchant(FORNO, "Forno Nero", 300, 25, true, 10, "Side door, Rue Ali");
        Merchant sushi = merchant(SUSHI, "Kaido Sushi", 400, 40, false, null, "");
        when(merchants.findById(FORNO)).thenReturn(Optional.of(forno));
        when(merchants.findById(SUSHI)).thenReturn(Optional.of(sushi));
        when(menuItems.findForMerchant(eq(FORNO), any()))
            .thenReturn(List.of(item(PIZZA_ITEM, "Margherita", 2_000)));
        when(menuItems.findForMerchant(eq(SUSHI), any()))
            .thenReturn(List.of(item(ROLL_ITEM, "Dragon roll", 3_000)));

        when(promotions.resolve(any(), any(), isNull(), anyInt(), anyInt(), anyBoolean()))
            .thenReturn(PromotionService.Applied.none());
        when(orders.save(any())).thenAnswer(returnsFirstArg());
        when(orders.findFirstByUserIdAndStatusNotInOrderByPlacedAtDesc(any(), any()))
            .thenReturn(Optional.empty());
        when(payments.currency()).thenReturn("USD");
    }

    // MARK: What a collection costs

    @Test
    @DisplayName("a pickup is charged no delivery fee and no tip")
    void aPickupHasNoFeeAndNoTip() {
        OrderDto placed = delivery.place(ME, pickup(50, basket(FORNO, PIZZA_ITEM, 1)));

        assertThat(placed.fulfilmentKind()).isEqualTo("PICKUP");
        assertThat(placed.deliveryFeeCents()).isZero();
        assertThat(placed.tipCents()).isZero();
        // The service fee is the platform's per checkout and is charged either
        // way (SPECS §5) — the courier's two lines are the only ones that go.
        assertThat(placed.serviceFeeCents()).isEqualTo(99);
        assertThat(placed.totalCents()).isEqualTo(2_000 + 99);
        assertThat(placed.subOrders()).singleElement()
            .extracting(SubOrderDto::deliveryFeeCents).isEqualTo(0);
    }

    /** A tip typed before switching to collection is dropped rather than made
     *  into a refusal: nobody should lose a checkout over changing their mind. */
    @Test
    void theTipIsDroppedRatherThanRefused() {
        QuoteDto quote = delivery.quote(ME, new QuoteRequest(FORNO,
            List.of(new OrderLineRequest(PIZZA_ITEM, 1)), null, null, 500, "PICKUP"));

        assertThat(quote.tipCents()).isZero();
        assertThat(quote.deliveryFeeCents()).isZero();
        assertThat(quote.fulfilmentKind()).isEqualTo("PICKUP");
        assertThat(quote.totalCents()).isEqualTo(2_000 + 99);
    }

    /** The delivery order is untouched by all of this, which is the wire
     *  compatibility claim stated as a test. */
    @Test
    void aDeliveryStillPricesExactlyAsItDid() {
        OrderDto placed = delivery.place(ME, new PlaceOrderRequest(FORNO,
            List.of(new OrderLineRequest(PIZZA_ITEM, 1)), null, null, "Home", "",
            null, 250, null, null));

        assertThat(placed.fulfilmentKind()).isEqualTo("DELIVERY");
        assertThat(placed.deliveryFeeCents()).isEqualTo(300);
        assertThat(placed.tipCents()).isEqualTo(250);
    }

    // MARK: Where it is collected from

    @Test
    @DisplayName("a pickup needs no delivery address, and copies the counter onto the slice")
    void aPickupNeedsNoAddress() {
        OrderDto placed = delivery.place(ME, pickup(0, basket(FORNO, PIZZA_ITEM, 1)));

        // Nothing was even looked up: requiring an address would mean nobody
        // could walk to a restaurant until they had saved somewhere to live.
        verify(addresses, org.mockito.Mockito.never()).findFirstByUserIdAndIsDefaultTrue(any());
        assertThat(placed.address().label()).isEmpty();
        assertThat(placed.subOrders()).singleElement()
            .extracting(SubOrderDto::pickupAddress)
            .isEqualTo("Side door, Rue Ali");
    }

    @Test
    @DisplayName("a merchant with no pickup line falls back to their name")
    void theCounterFallsBackToTheName() {
        Merchant forno = merchant(FORNO, "Forno Nero", 300, 25, true, 10, "");
        when(merchants.findById(FORNO)).thenReturn(Optional.of(forno));

        OrderDto placed = delivery.place(ME, pickup(0, basket(FORNO, PIZZA_ITEM, 1)));

        assertThat(placed.subOrders()).singleElement()
            .extracting(SubOrderDto::pickupAddress).isEqualTo("Forno Nero");
    }

    // MARK: Who may be collected from

    @Test
    @DisplayName("a restaurant that doesn't do collection refuses out loud")
    void collectionIsRefusedWhereItIsNotOffered() {
        assertThatThrownBy(() -> delivery.place(ME, pickup(0, basket(SUSHI, ROLL_ITEM, 1))))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("doesn't do collection")
            .extracting(e -> ((ResponseStatusException) e).getStatusCode())
            .isEqualTo(HttpStatus.CONFLICT);
    }

    /**
     * The refusal has to land on the whole checkout rather than on the one
     * basket: silently delivering the kitchen that cannot be collected from
     * would split one order into two fulfilments, which is the thing the kind
     * living on the order exists to prevent.
     */
    @Test
    void oneKitchenWithoutCollectionRefusesTheWholeCheckout() {
        assertThatThrownBy(() -> delivery.place(ME,
            pickup(0, basket(FORNO, PIZZA_ITEM, 1), basket(SUSHI, ROLL_ITEM, 1))))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Kaido Sushi");
    }

    @Test
    @DisplayName("collecting from two kitchens that both offer it is allowed")
    void twoCountersAreFine() {
        Merchant sushi = merchant(SUSHI, "Kaido Sushi", 400, 40, true, null, "");
        when(merchants.findById(SUSHI)).thenReturn(Optional.of(sushi));

        OrderDto placed = delivery.place(ME,
            pickup(0, basket(FORNO, PIZZA_ITEM, 1), basket(SUSHI, ROLL_ITEM, 1)));

        assertThat(placed.subOrders()).hasSize(2);
        assertThat(placed.deliveryFeeCents()).isZero();
        assertThat(placed.totalCents()).isEqualTo(5_000 + 99);
    }

    // MARK: Promotions

    @Test
    @DisplayName("the pickup flag reaches the promotion resolver")
    void thePromotionResolverIsToldItIsACollection() {
        delivery.place(ME, pickup(0, basket(FORNO, PIZZA_ITEM, 1)));

        verify(promotions).resolve(eq(FORNO), eq(ME), isNull(), eq(2_000), eq(0), eq(true));
    }

    @Test
    void aDeliveryTellsItTheOppositeAndPassesTheRealFee() {
        delivery.place(ME, new PlaceOrderRequest(FORNO,
            List.of(new OrderLineRequest(PIZZA_ITEM, 1)), null, null, "Home", "",
            null, 0, null, null));

        verify(promotions).resolve(eq(FORNO), eq(ME), isNull(), eq(2_000), eq(300), eq(false));
    }

    // MARK: Helpers

    private PlaceOrderRequest pickup(int tipCents, BasketRequest... baskets) {
        return new PlaceOrderRequest(null, null, List.of(baskets), null, null, "",
            null, tipCents, null, "PICKUP");
    }

    private static BasketRequest basket(UUID merchantId, UUID itemId, int qty) {
        return new BasketRequest(merchantId, List.of(new OrderLineRequest(itemId, qty)), null);
    }

    private static Merchant merchant(UUID id, String name, int deliveryFeeCents, int etaMinutes,
                                     boolean pickupEnabled, Integer pickupPrepMinutes,
                                     String pickupAddress) {
        Merchant merchant = new Merchant(UUID.randomUUID(), name, "Kitchen", null, 33.57, -7.58);
        set(merchant, "id", id);
        set(merchant, "deliveryFeeCents", deliveryFeeCents);
        set(merchant, "etaMinutes", etaMinutes);
        set(merchant, "pickupEnabled", pickupEnabled);
        set(merchant, "pickupPrepMinutes", pickupPrepMinutes);
        set(merchant, "pickupAddress", pickupAddress);
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
