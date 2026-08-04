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
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The handover from a simulated fulfilment to a real one.
 *
 * <p>Everything here is a case the old {@code OrderFulfilmentJob} could not
 * reach, because a timeline that walks every order forward has no failures: no
 * restaurant that says no, nobody who never answers, no city with no couriers
 * in it. Those are now the interesting states, and each of them ends with
 * somebody's money in the wrong place if it is wrong.
 */
class CourierFulfilmentTests {

    private static final UUID OWNER = UUID.randomUUID();
    private static final UUID CUSTOMER = UUID.randomUUID();
    private static final UUID MERCHANT = UUID.randomUUID();
    private static final UUID COURIER_USER = UUID.randomUUID();
    private static final UUID COURIER_WORKER = UUID.randomUUID();
    private static final UUID ORDER = UUID.randomUUID();
    private static final UUID SLICE = UUID.randomUUID();

    private OrderRepository orders;
    private SubOrderRepository subOrders;
    private MerchantRepository merchants;
    private OrderPayments payments;
    private DispatchApi dispatch;
    private ProfileApi profiles;
    private MessagingApi messaging;
    private MediaDocumentApi privateMedia;
    private ApplicationEventPublisher events;
    private OrderFulfilmentService service;
    private CustomerOrder order;
    private SubOrder slice;
    private Merchant merchant;

    @BeforeEach
    void setUp() {
        orders = mock(OrderRepository.class);
        subOrders = mock(SubOrderRepository.class);
        merchants = mock(MerchantRepository.class);
        payments = mock(OrderPayments.class);
        dispatch = mock(DispatchApi.class);
        profiles = mock(ProfileApi.class);
        messaging = mock(MessagingApi.class);
        privateMedia = mock(MediaDocumentApi.class);
        events = mock(ApplicationEventPublisher.class);

        DeliveryPolicy policy = new DeliveryPolicy(new StubConfig());
        service = new OrderFulfilmentService(orders, subOrders, merchants, payments, policy,
            dispatch, profiles, messaging, privateMedia, events);

        merchant = new Merchant(OWNER, "Forno Nero", "Pizza", null, 33.57, -7.58);
        set(merchant, "id", MERCHANT);
        when(merchants.findFirstByOwnerId(OWNER)).thenReturn(Optional.of(merchant));
        when(merchants.findById(MERCHANT)).thenReturn(Optional.of(merchant));
        when(merchants.findAllById(any())).thenReturn(List.of(merchant));

        order = new CustomerOrder(CUSTOMER, "USD", "Second floor",
            OffsetDateTime.now().plusMinutes(30));
        set(order, "id", ORDER);
        order.deliverTo(null, "Home", "12 Rue Ali", "", 33.58, -7.60);
        slice = order.addSubOrder(MERCHANT, 2_000, 300, 0, null, "");
        set(slice, "id", SLICE);
        order.priceIt(Basket.of(MERCHANT, 2_000, 300, 99, 0, 0, "USD"));
        when(orders.findById(ORDER)).thenReturn(Optional.of(order));
        when(subOrders.findById(SLICE)).thenReturn(Optional.of(slice));
    }

    // MARK: The kitchen decides, and the search is timed to it

    @Test
    @DisplayName("accepting schedules the courier search for just before the food is ready")
    void acceptSchedulesTheSearchAtReadyMinusLead() {
        service.accept(OWNER, SLICE, 30);

        ArgumentCaptor<DispatchRequest> request = ArgumentCaptor.forClass(DispatchRequest.class);
        verify(dispatch).request(request.capture());
        DispatchRequest asked = request.getValue();

        assertThat(asked.jobKind()).isEqualTo(JobKind.DELIVERY);
        assertThat(asked.jobRefId()).isEqualTo(ORDER);
        assertThat(asked.workerKind()).isEqualTo(WorkerKind.COURIER);
        // 30 min of cooking, minus the 7 min lead: 23 minutes from now. This is
        // the whole of SPECS §3's "approaching readiness" trigger, and it is
        // startAfter rather than a mechanism of delivery's own.
        assertThat(asked.startAfter()).isEqualTo(order.getReadyAt().minusSeconds(420));
        assertThat(order.getStatus()).isEqualTo(OrderStatus.PREPARING);
        assertThat(order.getCourierSearch()).isEqualTo(CourierSearch.SEARCHING);
    }

    /** A basket that fits on a bike also fits in a car — asking only for bikes
     *  on a night with none out is a dinner nobody delivers. */
    @Test
    void theSearchAcceptsEveryCategoryThatCouldCarryIt() {
        service.accept(OWNER, SLICE, 20);

        ArgumentCaptor<DispatchRequest> request = ArgumentCaptor.forClass(DispatchRequest.class);
        verify(dispatch).request(request.capture());
        assertThat(request.getValue().categories())
            .containsExactlyInAnyOrder(VehicleCategory.BIKE, VehicleCategory.SCOOTER,
                VehicleCategory.CAR);
    }

    /** An accept that can fail validation is an accept somebody in a kitchen
     *  does not make. */
    @Test
    void aMissingPrepEstimateFallsBackRatherThanRefusing() {
        service.accept(OWNER, SLICE, null);
        assertThat(slice.getPrepMinutes()).isEqualTo(20);
        assertThat(order.getStatus()).isEqualTo(OrderStatus.PREPARING);
    }

    /** A typo of 600 for 60 would hold the customer's money for ten hours and
     *  schedule a courier for tomorrow morning. */
    @Test
    void anAbsurdPrepEstimateIsCapped() {
        service.accept(OWNER, SLICE, 6_000);
        assertThat(slice.getPrepMinutes()).isEqualTo(180);
    }

    @Test
    @DisplayName("dispatch having a bad moment does not un-accept the order")
    void aFailedSearchDoesNotFailTheAccept() {
        when(dispatch.request(any())).thenThrow(new IllegalStateException("dispatch is down"));

        service.accept(OWNER, SLICE, 20);

        // The kitchen is cooking. Rolling that back over dispatch would be worse
        // than an order that visibly has nobody coming for it.
        assertThat(order.getStatus()).isEqualTo(OrderStatus.PREPARING);
        assertThat(order.getCourierSearch()).isEqualTo(CourierSearch.FAILED);
    }

    @Test
    void acceptingTwiceIsRefusedRatherThanReSearching() {
        service.accept(OWNER, SLICE, 20);
        assertThatThrownBy(() -> service.accept(OWNER, SLICE, 20))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("already accepted");
        verify(dispatch).request(any());
    }

    @Test
    @DisplayName("a rejection gives the money back in the same transaction")
    void rejectingReleasesTheHold() {
        service.reject(OWNER, SLICE, "We're out of dough");

        assertThat(order.getStatus()).isEqualTo(OrderStatus.CANCELLED);
        assertThat(order.getCancelReason()).isEqualTo("We're out of dough");
        verify(payments).release(order);
        verify(dispatch).cancel(JobKind.DELIVERY, ORDER, false);
    }

    /** Once a kitchen has started, "reject" is a cancellation with food already
     *  made — a dispute (SPECS §5), not a button. */
    @Test
    void rejectingAfterAcceptingIsRefused() {
        service.accept(OWNER, SLICE, 20);
        assertThatThrownBy(() -> service.reject(OWNER, SLICE, "changed our mind"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Too late");
    }

    /** 404 rather than 403: another restaurant's order is not theirs to learn
     *  the existence of. */
    @Test
    void anotherRestaurantsOrderIsNotFound() {
        Merchant somebodyElse = new Merchant(OWNER, "Kaido Sushi", "Sushi", null, 0d, 0d);
        set(somebodyElse, "id", UUID.randomUUID());
        when(merchants.findFirstByOwnerId(OWNER)).thenReturn(Optional.of(somebodyElse));

        assertThatThrownBy(() -> service.accept(OWNER, SLICE, 20))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("No such order");
    }

    // MARK: A real person takes it

    @Test
    @DisplayName("the assignment puts a real courier on the order")
    void assignmentReplacesTheHardcodedRoster() {
        service.accept(OWNER, SLICE, 20);
        when(profiles.findById(COURIER_USER)).thenReturn(Optional.of(profile("Yassine B.")));

        service.courierAssigned(ORDER, assignment());

        assertThat(order.getStatus()).isEqualTo(OrderStatus.COURIER_TO_RESTAURANT);
        assertThat(order.getCourierUserId()).isEqualTo(COURIER_USER);
        assertThat(order.getCourierWorkerId()).isEqualTo(COURIER_WORKER);
        assertThat(order.getCourierName()).isEqualTo("Yassine B.");
        assertThat(order.getCourierVehicle()).isEqualTo("Red Honda scooter");
        assertThat(order.getCourierSearch()).isEqualTo(CourierSearch.ASSIGNED);
    }

    /**
     * The race the customer can win: they cancel between the accept and the
     * assignment. Leaving the courier assigned would make them BUSY for an order
     * nobody is waiting on, and nothing would ever free them.
     */
    @Test
    void aCourierAssignedToACancelledOrderIsHandedStraightBack() {
        service.reject(OWNER, SLICE, "Closed");

        service.courierAssigned(ORDER, assignment());

        assertThat(order.getCourierUserId()).isNull();
        // Once for the rejection, once for handing the courier back.
        verify(dispatch, org.mockito.Mockito.times(2)).cancel(JobKind.DELIVERY, ORDER, false);
    }

    /**
     * A redelivered event, which an at-least-once listener has to survive. The
     * dangerous reading is "not PREPARING means it was cancelled" — that would
     * stand a courier down from a delivery they are halfway through, on nothing
     * more than a duplicate message.
     */
    @Test
    void aRepeatedAssignmentDoesNotStandTheCourierDown() {
        service.accept(OWNER, SLICE, 20);
        service.courierAssigned(ORDER, assignment());
        collect();

        service.courierAssigned(ORDER, assignment());

        assertThat(order.getStatus()).isEqualTo(OrderStatus.DELIVERING);
        assertThat(order.getCourierUserId()).isEqualTo(COURIER_USER);
        verify(dispatch, never()).cancel(any(), any(), anyBoolean());
    }

    @Test
    @DisplayName("nobody took it: flagged, not cancelled")
    void anExhaustedSearchDoesNotThrowAwayCookedFood()  {
        service.accept(OWNER, SLICE, 20);

        service.courierSearchFailed(ORDER);

        assertThat(order.getCourierSearch()).isEqualTo(CourierSearch.FAILED);
        assertThat(order.getStatus()).isEqualTo(OrderStatus.PREPARING);
        verify(payments, never()).release(any());
    }

    // MARK: The trip

    @Test
    void onlyTheAssignedCourierCanMoveTheOrder() {
        service.accept(OWNER, SLICE, 20);
        service.courierAssigned(ORDER, assignment());

        assertThatThrownBy(() -> service.pickedUp(UUID.randomUUID(), ORDER, slice.getPickupCode()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("No such order");
    }

    @Test
    void deliveringBeforePickingUpIsRefused() {
        service.accept(OWNER, SLICE, 20);
        service.courierAssigned(ORDER, assignment());

        assertThatThrownBy(() -> handOver())
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Pick the order up first");
        verify(payments, never()).settle(any(), any());
    }

    @Test
    @DisplayName("handing it over is the one transition that moves money")
    void deliveringSettlesAndFreesTheCourier() {
        service.accept(OWNER, SLICE, 20);
        service.courierAssigned(ORDER, assignment());
        collect();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.DELIVERING);

        handOver();

        assertThat(order.getStatus()).isEqualTo(OrderStatus.DELIVERED);
        verify(payments).settle(order, java.util.Map.of(MERCHANT, "Forno Nero"));
        // Null, not the order rating: a two star for a cold burger is about the
        // food, and must not land on the record of whoever cycled it over.
        verify(dispatch).complete(JobKind.DELIVERY, ORDER, null);
    }

    @Test
    void deliveringTwiceCannotPayTwice() {
        service.accept(OWNER, SLICE, 20);
        service.courierAssigned(ORDER, assignment());
        collect();
        handOver();

        assertThatThrownBy(() -> handOver())
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("already delivered");
        verify(payments).settle(any(), any());
    }

    // MARK: Nobody answered

    /**
     * The failure a simulation could not have: a restaurant that never looks at
     * their tablet. Without the sweep the customer's money sits in escrow and
     * their one live-order slot with it, forever, and nothing in the system ever
     * looks at that row again.
     */
    @Test
    @DisplayName("an unanswered order is cancelled and released, not left")
    void theTimeoutReleasesTheHold() {
        service.timeOut(SLICE);

        assertThat(order.getStatus()).isEqualTo(OrderStatus.CANCELLED);
        assertThat(order.getCancelReason()).contains("didn't answer");
        verify(payments).release(order);
    }

    /** The sweep runs on a batch read from a moment ago; by the time it gets
     *  here the kitchen may have accepted. */
    @Test
    void theTimeoutSkipsAnOrderAcceptedInTheMeantime() {
        service.accept(OWNER, SLICE, 20);

        service.timeOut(SLICE);

        assertThat(order.getStatus()).isEqualTo(OrderStatus.PREPARING);
        verify(payments, never()).release(any());
    }

    // MARK: What the customer is told

    @Test
    @DisplayName("every transition still publishes the same event the app reads")
    void statusChangesArePublished() {
        service.accept(OWNER, SLICE, 20);
        service.courierAssigned(ORDER, assignment());
        collect();
        handOver();

        ArgumentCaptor<Object> published = ArgumentCaptor.forClass(Object.class);
        verify(events, org.mockito.Mockito.atLeast(4)).publishEvent(published.capture());
        assertThat(published.getAllValues())
            .filteredOn(OrderStatusChanged.class::isInstance)
            .extracting(e -> ((OrderStatusChanged) e).status())
            .containsExactly("PREPARING", "COURIER_TO_RESTAURANT", "DELIVERING", "DELIVERED");
    }

    // MARK: Helpers

    /**
     * The two courier taps, with the codes M2 mints at accept. They are one line
     * each here on purpose: this file is about the state machine and the money,
     * and what happens when a code is <em>wrong</em> belongs in
     * {@link HandoffTests}.
     */
    private HandoffResultDto collect() {
        return service.pickedUp(COURIER_USER, ORDER, slice.getPickupCode());
    }

    private HandoffResultDto handOver() {
        return service.delivered(COURIER_USER, ORDER, order.getDeliveryPin());
    }

    private Assignment assignment() {
        return new Assignment(COURIER_WORKER, COURIER_USER, WorkerKind.COURIER,
            VehicleCategory.SCOOTER, JobKind.DELIVERY, ORDER, 4.9, 214,
            new VehicleRef(UUID.randomUUID(), VehicleCategory.SCOOTER,
                "Red Honda scooter", "9911-B-2", false),
            OffsetDateTime.now());
    }

    private static ProfileDto profile(String displayName) {
        return new ProfileDto(COURIER_USER, "sub", "courier@example.com", displayName,
            "yassine", "", "", null, null, java.util.Set.of(),
            com.gojogo.profile.ProfileKind.PERSON, null, false);
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

    /** The registry with nothing in it — every default in {@link DeliveryPolicy}
     *  matches the row V35 seeds, so this is also a test that they do. */
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
