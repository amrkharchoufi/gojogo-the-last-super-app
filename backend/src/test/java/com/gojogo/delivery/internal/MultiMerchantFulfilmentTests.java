package com.gojogo.delivery.internal;

import com.gojogo.delivery.OrderStatusChanged;
import com.gojogo.dispatch.Assignment;
import com.gojogo.dispatch.DispatchApi;
import com.gojogo.dispatch.DispatchRequest;
import com.gojogo.dispatch.JobKind;
import com.gojogo.dispatch.VehicleCategory;
import com.gojogo.dispatch.VehicleRef;
import com.gojogo.dispatch.WorkerKind;
import com.gojogo.media.MediaDocumentApi;
import com.gojogo.messaging.MessagingApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.web.server.ResponseStatusException;

import java.lang.reflect.Field;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * An order across two kitchens, from the kitchens' and the courier's side
 * (Phase 4 M3). The cases here are the ones a single-merchant order cannot
 * have: a search that must wait for the slower kitchen, a slice that dies
 * while its sibling cooks, and a courier who has one bag and not the other.
 */
class MultiMerchantFulfilmentTests {

    private static final UUID FORNO_OWNER = UUID.randomUUID();
    private static final UUID SUSHI_OWNER = UUID.randomUUID();
    private static final UUID CUSTOMER = UUID.randomUUID();
    private static final UUID FORNO = UUID.randomUUID();
    private static final UUID SUSHI = UUID.randomUUID();
    private static final UUID COURIER_USER = UUID.randomUUID();
    private static final UUID ORDER = UUID.randomUUID();
    private static final UUID FORNO_SLICE = UUID.randomUUID();
    private static final UUID SUSHI_SLICE = UUID.randomUUID();

    private OrderRepository orders;
    private SubOrderRepository subOrders;
    private MerchantRepository merchants;
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
        merchants = mock(MerchantRepository.class);
        payments = mock(OrderPayments.class);
        dispatch = mock(DispatchApi.class);
        ProfileApi profiles = mock(ProfileApi.class);
        events = mock(ApplicationEventPublisher.class);

        service = new OrderFulfilmentService(orders, subOrders, merchants, payments,
            new DeliveryPolicy(new StubConfig()), dispatch, profiles,
            mock(MessagingApi.class), mock(MediaDocumentApi.class), events);

        Merchant forno = new Merchant(FORNO_OWNER, "Forno Nero", "Pizza", null, 33.57, -7.58);
        set(forno, "id", FORNO);
        Merchant sushi = new Merchant(SUSHI_OWNER, "Kaido Sushi", "Sushi", null, 33.59, -7.61);
        set(sushi, "id", SUSHI);
        when(merchants.findFirstByOwnerId(FORNO_OWNER)).thenReturn(Optional.of(forno));
        when(merchants.findFirstByOwnerId(SUSHI_OWNER)).thenReturn(Optional.of(sushi));
        when(merchants.findById(FORNO)).thenReturn(Optional.of(forno));
        when(merchants.findById(SUSHI)).thenReturn(Optional.of(sushi));
        when(merchants.findAllById(any())).thenReturn(List.of(forno, sushi));
        when(profiles.findById(COURIER_USER)).thenReturn(Optional.of(
            new ProfileDto(COURIER_USER, "sub", "c@example.com", "Yassine B.", "yassine",
                "", "", null, null, java.util.Set.of(),
                com.gojogo.profile.ProfileKind.PERSON, null, false)));

        order = new CustomerOrder(CUSTOMER, "USD", "", OffsetDateTime.now().plusMinutes(40));
        set(order, "id", ORDER);
        order.deliverTo(null, "Home", "12 Rue Ali", "", 33.58, -7.60);
        fornoSlice = order.addSubOrder(FORNO, 2_000, 300, 0, null, "");
        set(fornoSlice, "id", FORNO_SLICE);
        sushiSlice = order.addSubOrder(SUSHI, 3_000, 400, 0, null, "");
        set(sushiSlice, "id", SUSHI_SLICE);
        order.priceIt(Basket.of(List.of(
                Basket.MerchantSlice.of(FORNO, 2_000, 300, 0, null, "", ""),
                Basket.MerchantSlice.of(SUSHI, 3_000, 400, 0, null, "", "")),
            99, 250, "USD"));
        when(orders.findById(ORDER)).thenReturn(Optional.of(order));
        when(subOrders.findById(FORNO_SLICE)).thenReturn(Optional.of(fornoSlice));
        when(subOrders.findById(SUSHI_SLICE)).thenReturn(Optional.of(sushiSlice));
    }

    // MARK: The search waits for the slowest kitchen

    @Test
    @DisplayName("no courier search opens while a kitchen is still deciding")
    void theSearchWaitsForEveryAnswer() {
        service.accept(FORNO_OWNER, FORNO_SLICE, 20);

        assertThat(order.getStatus()).isEqualTo(OrderStatus.PREPARING);
        assertThat(order.getCourierSearch()).isEqualTo(CourierSearch.NONE);
        verify(dispatch, never()).request(any());
    }

    @Test
    @DisplayName("the search opens on the last answer, timed to the slowest kitchen")
    void theSearchIsTimedToTheSlowestKitchen() {
        service.accept(FORNO_OWNER, FORNO_SLICE, 15);
        service.accept(SUSHI_OWNER, SUSHI_SLICE, 45);

        ArgumentCaptor<DispatchRequest> request = ArgumentCaptor.forClass(DispatchRequest.class);
        verify(dispatch).request(request.capture());
        // max(readyAt) is the sushi kitchen's 45 minutes; lead is the default 420 s.
        assertThat(request.getValue().startAfter())
            .isEqualTo(sushiSlice.getReadyAt().minusSeconds(420));
        assertThat(order.getReadyAt()).isEqualTo(sushiSlice.getReadyAt());
        assertThat(order.getCourierSearch()).isEqualTo(CourierSearch.SEARCHING);
    }

    /** A rejection is an answer too: the search must open for whatever
     *  survived, not wait forever on a kitchen that already said no. */
    @Test
    void aRejectionCountsAsTheAnswerTheSearchWasWaitingOn() {
        service.accept(FORNO_OWNER, FORNO_SLICE, 20);
        service.reject(SUSHI_OWNER, SUSHI_SLICE, "Out of rice");

        verify(dispatch).request(any());
        assertThat(order.getCourierSearch()).isEqualTo(CourierSearch.SEARCHING);
        // And the clock re-derives around the kitchen that remains.
        assertThat(order.getReadyAt()).isEqualTo(fornoSlice.getReadyAt());
    }

    // MARK: One slice dies, the order lives

    @Test
    @DisplayName("a rejected slice releases exactly its own share")
    void aRejectedSliceReleasesItsShare() {
        service.accept(FORNO_OWNER, FORNO_SLICE, 20);

        service.reject(SUSHI_OWNER, SUSHI_SLICE, "Out of rice");

        assertThat(sushiSlice.getStatus()).isEqualTo(SubOrderStatus.CANCELLED);
        assertThat(sushiSlice.getCancelReason()).isEqualTo("Out of rice");
        verify(payments).releaseSubOrder(order, sushiSlice, "Kaido Sushi");
        verify(payments, never()).release(any());
        assertThat(order.getStatus()).isEqualTo(OrderStatus.PREPARING);
        // The customer hears about it even though the order's status never
        // moved — it is its own word, which older clients simply drop.
        ArgumentCaptor<Object> published = ArgumentCaptor.forClass(Object.class);
        verify(events, org.mockito.Mockito.atLeastOnce()).publishEvent(published.capture());
        assertThat(published.getAllValues())
            .filteredOn(OrderStatusChanged.class::isInstance)
            .extracting(e -> ((OrderStatusChanged) e).status())
            .contains("SUB_CANCELLED");
    }

    /** The last live slice takes the order with it, and the whole remainder is
     *  released in one movement rather than a share plus a rump. */
    @Test
    void theLastSliceCancellingEndsTheOrder() {
        service.reject(FORNO_OWNER, FORNO_SLICE, "Closed");
        service.reject(SUSHI_OWNER, SUSHI_SLICE, "Out of rice");

        assertThat(order.getStatus()).isEqualTo(OrderStatus.CANCELLED);
        // Forno's share was released on its own; the final cancel releases the
        // rest (sushi's share + the service fee + the tip) in one movement.
        verify(payments).releaseSubOrder(order, fornoSlice, "Forno Nero");
        verify(payments).release(order);
        verify(dispatch).cancel(JobKind.DELIVERY, ORDER, false);
    }

    /** The slice nobody answered times out alone; the kitchen that answered
     *  keeps cooking. */
    @Test
    void aTimeoutTakesOnlyTheSilentKitchen() {
        service.accept(FORNO_OWNER, FORNO_SLICE, 20);

        service.timeOut(SUSHI_SLICE);

        assertThat(sushiSlice.getStatus()).isEqualTo(SubOrderStatus.CANCELLED);
        assertThat(fornoSlice.getStatus()).isEqualTo(SubOrderStatus.PREPARING);
        assertThat(order.getStatus()).isEqualTo(OrderStatus.PREPARING);
        verify(payments).releaseSubOrder(order, sushiSlice, "Kaido Sushi");
    }

    // MARK: The courier proves every counter

    @Test
    @DisplayName("each code collects its own kitchen's bag, and only the last one moves the order")
    void eachCodeCollectsItsOwnBag() {
        bothAcceptedAndAssigned();

        HandoffResultDto first = service.pickedUp(COURIER_USER, ORDER,
            fornoSlice.getPickupCode());

        assertThat(first.accepted()).isTrue();
        assertThat(first.message()).contains("1 more pickup");
        assertThat(fornoSlice.getStatus()).isEqualTo(SubOrderStatus.COLLECTED);
        assertThat(sushiSlice.getStatus()).isEqualTo(SubOrderStatus.PREPARING);
        assertThat(order.getStatus()).isEqualTo(OrderStatus.COURIER_TO_RESTAURANT);

        HandoffResultDto second = service.pickedUp(COURIER_USER, ORDER,
            sushiSlice.getPickupCode());

        assertThat(second.accepted()).isTrue();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.DELIVERING);
    }

    @Test
    void theSameCodeCannotCollectTheOtherKitchensBag() {
        bothAcceptedAndAssigned();
        service.pickedUp(COURIER_USER, ORDER, fornoSlice.getPickupCode());

        HandoffResultDto again = service.pickedUp(COURIER_USER, ORDER,
            fornoSlice.getPickupCode());

        assertThat(again.accepted()).isFalse();
        assertThat(sushiSlice.getStatus()).isEqualTo(SubOrderStatus.PREPARING);
        assertThat(order.getStatus()).isEqualTo(OrderStatus.COURIER_TO_RESTAURANT);
    }

    /** Two codes exist and they are different — a code that could open both
     *  counters would prove presence at neither. */
    @Test
    void everyKitchenMintsItsOwnCode() {
        service.accept(FORNO_OWNER, FORNO_SLICE, 15);
        service.accept(SUSHI_OWNER, SUSHI_SLICE, 45);

        assertThat(fornoSlice.getPickupCode()).hasSize(6).containsOnlyDigits();
        assertThat(sushiSlice.getPickupCode()).hasSize(6).containsOnlyDigits();
        assertThat(fornoSlice.getPickupCode()).isNotEqualTo(sushiSlice.getPickupCode());
        // One door, one PIN — minted at the first accept and never re-minted.
        assertThat(order.getDeliveryPin()).hasSize(6).containsOnlyDigits();
    }

    @Test
    void theCourierStopsListEveryKitchenWithItsCollectedFlag() {
        bothAcceptedAndAssigned();
        service.pickedUp(COURIER_USER, ORDER, fornoSlice.getPickupCode());

        CourierJobDto job = service.job(COURIER_USER).job();

        assertThat(job.stops()).hasSize(2);
        assertThat(job.stops())
            .filteredOn(CourierStopDto::collected)
            .singleElement()
            .extracting(CourierStopDto::subOrderId)
            .isEqualTo(FORNO_SLICE);
        // The legacy single-merchant fields point at the next uncollected
        // counter, so an older client is still guided to the right place.
        assertThat(job.merchantName()).isEqualTo("Kaido Sushi");
        // The pay is every surviving stop's fee plus the tip.
        assertThat(job.payMinor()).isEqualTo(300 + 400 + 250);
    }

    // MARK: The settlement across kitchens

    /** Delivery stamps every surviving slice, so a settlement over the slices
     *  pays both kitchens and the courier every stop's fee. */
    @Test
    void deliveryStampsEverySurvivingSlice() {
        bothAcceptedAndAssigned();
        service.pickedUp(COURIER_USER, ORDER, fornoSlice.getPickupCode());
        service.pickedUp(COURIER_USER, ORDER, sushiSlice.getPickupCode());

        HandoffResultDto result = service.delivered(COURIER_USER, ORDER,
            order.getDeliveryPin());

        assertThat(result.accepted()).isTrue();
        assertThat(fornoSlice.getStatus()).isEqualTo(SubOrderStatus.DELIVERED);
        assertThat(sushiSlice.getStatus()).isEqualTo(SubOrderStatus.DELIVERED);
        verify(payments).settle(order, java.util.Map.of(
            FORNO, "Forno Nero", SUSHI, "Kaido Sushi"));
    }

    /** A slice cancelled before the trip must stay CANCELLED through delivery —
     *  DELIVERED on a refunded slice would pay its kitchen for food that was
     *  never made. */
    @Test
    void aCancelledSliceIsNeverStampedDelivered() {
        service.accept(FORNO_OWNER, FORNO_SLICE, 20);
        service.reject(SUSHI_OWNER, SUSHI_SLICE, "Out of rice");
        service.courierAssigned(ORDER, assignment());
        service.pickedUp(COURIER_USER, ORDER, fornoSlice.getPickupCode());

        service.delivered(COURIER_USER, ORDER, order.getDeliveryPin());

        assertThat(fornoSlice.getStatus()).isEqualTo(SubOrderStatus.DELIVERED);
        assertThat(sushiSlice.getStatus()).isEqualTo(SubOrderStatus.CANCELLED);
    }

    // MARK: The kitchen's own view

    @Test
    @DisplayName("a kitchen's queue row is their slice in the six words their screen has always spoken")
    void theKitchenSeesTheirSliceInTheOldVocabulary() {
        bothAcceptedAndAssigned();
        service.pickedUp(COURIER_USER, ORDER, fornoSlice.getPickupCode());
        when(subOrders.queueFor(org.mockito.ArgumentMatchers.eq(FORNO), any()))
            .thenReturn(List.of(fornoSlice));
        when(subOrders.queueFor(org.mockito.ArgumentMatchers.eq(SUSHI), any()))
            .thenReturn(List.of(sushiSlice));

        MerchantOrderDto fornoRow = service.queue(FORNO_OWNER).getFirst();
        MerchantOrderDto sushiRow = service.queue(SUSHI_OWNER).getFirst();

        // Forno's bag is in the courier's hand; sushi's is still cooking with
        // the courier en route. Same order, two honest rows.
        assertThat(fornoRow.status()).isEqualTo("DELIVERING");
        assertThat(sushiRow.status()).isEqualTo("COURIER_TO_RESTAURANT");
        // Each kitchen sees their own money and their own code, not the order's.
        assertThat(fornoRow.subtotalCents()).isEqualTo(2_000);
        assertThat(sushiRow.subtotalCents()).isEqualTo(3_000);
        assertThat(fornoRow.pickupCode()).isEqualTo(fornoSlice.getPickupCode());
        assertThat(sushiRow.pickupCode()).isEqualTo(sushiSlice.getPickupCode());
    }

    /** One kitchen cannot answer for another — a sub-order id that is not
     *  yours is a 404, exactly like an order that is not yours. */
    @Test
    void oneKitchenCannotAcceptAnothersSlice() {
        assertThatThrownBy(() -> service.accept(FORNO_OWNER, SUSHI_SLICE, 20))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("No such order");
    }

    // MARK: Helpers

    private void bothAcceptedAndAssigned() {
        service.accept(FORNO_OWNER, FORNO_SLICE, 15);
        service.accept(SUSHI_OWNER, SUSHI_SLICE, 25);
        service.courierAssigned(ORDER, assignment());
        when(orders.findFirstByCourierUserIdAndStatusInOrderByStatusChangedAtDesc(
            org.mockito.ArgumentMatchers.eq(COURIER_USER), any()))
            .thenReturn(Optional.of(order));
    }

    private Assignment assignment() {
        return new Assignment(UUID.randomUUID(), COURIER_USER, WorkerKind.COURIER,
            VehicleCategory.SCOOTER, JobKind.DELIVERY, ORDER, 4.9, 214,
            new VehicleRef(UUID.randomUUID(), VehicleCategory.SCOOTER,
                "Red Honda scooter", "9911-B-2", false),
            OffsetDateTime.now());
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
