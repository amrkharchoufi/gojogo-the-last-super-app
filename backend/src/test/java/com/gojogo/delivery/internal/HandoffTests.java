package com.gojogo.delivery.internal;

import com.gojogo.dispatch.Assignment;
import com.gojogo.dispatch.DispatchApi;
import com.gojogo.dispatch.JobKind;
import com.gojogo.dispatch.VehicleCategory;
import com.gojogo.dispatch.VehicleRef;
import com.gojogo.dispatch.WorkerKind;
import com.gojogo.media.MediaDocumentApi;
import com.gojogo.messaging.ConversationContext;
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
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Handoff integrity: the two courier taps, and what happens when the person
 * making them cannot prove they should.
 *
 * <p>M1's tests were about a state machine driven by real people for the first
 * time. These are about the gap that left: both taps moved an order on nothing
 * but somebody's word, and the second one paid them for it. So every case here
 * is a way of being wrong at a counter or at a door — a mistyped code, a
 * customer who will not answer, a photo that was never taken — and the thing
 * being asserted is usually that the system said so <em>without</em> moving the
 * status or the money, because a refusal that half-completes a delivery is worse
 * than no check at all.
 */
class HandoffTests {

    private static final UUID OWNER = UUID.randomUUID();
    private static final UUID CUSTOMER = UUID.randomUUID();
    private static final UUID MERCHANT = UUID.randomUUID();
    private static final UUID COURIER_USER = UUID.randomUUID();
    private static final UUID COURIER_WORKER = UUID.randomUUID();
    private static final UUID ORDER = UUID.randomUUID();
    private static final UUID SLICE = UUID.randomUUID();
    private static final UUID CONVERSATION = UUID.randomUUID();

    private OrderRepository orders;
    private SubOrderRepository subOrders;
    private MerchantRepository merchants;
    private OrderPayments payments;
    private DispatchApi dispatch;
    private ProfileApi profiles;
    private MessagingApi messaging;
    private MediaDocumentApi privateMedia;
    private OrderFulfilmentService service;
    private CustomerOrder order;
    private SubOrder slice;

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
        ApplicationEventPublisher events = mock(ApplicationEventPublisher.class);

        service = new OrderFulfilmentService(orders, subOrders, merchants, payments,
            new DeliveryPolicy(new StubConfig()), dispatch, profiles, messaging,
            privateMedia, events);

        Merchant merchant = new Merchant(OWNER, "Forno Nero", "Pizza",
            "https://cdn.example/forno.jpg", 33.57, -7.58);
        set(merchant, "id", MERCHANT);
        when(merchants.findFirstByOwnerId(OWNER)).thenReturn(Optional.of(merchant));
        when(merchants.findById(MERCHANT)).thenReturn(Optional.of(merchant));
        when(merchants.findAllById(any())).thenReturn(java.util.List.of(merchant));
        when(messaging.openDirectConversation(any(), any(), any())).thenReturn(CONVERSATION);
        when(profiles.findById(COURIER_USER)).thenReturn(Optional.of(profile()));

        order = new CustomerOrder(CUSTOMER, "USD", "Second floor",
            OffsetDateTime.now().plusMinutes(30));
        set(order, "id", ORDER);
        order.deliverTo(null, "Home", "12 Rue Ali", "", 33.58, -7.60);
        slice = order.addSubOrder(MERCHANT, 2_000, 300, 0, null, "");
        set(slice, "id", SLICE);
        order.priceIt(Basket.of(MERCHANT, 2_000, 300, 99, 0, 0, "USD"));
        order.addLine(slice, UUID.randomUUID(), "Margherita", 2_000, 2);
        when(orders.findById(ORDER)).thenReturn(Optional.of(order));
        when(subOrders.findById(SLICE)).thenReturn(Optional.of(slice));
    }

    // MARK: Minting

    /**
     * Both codes exist from the accept, and neither exists before it. The timing
     * is the design: a code on an order the restaurant may still refuse is a
     * code for a delivery that never happens, and a code minted any later is a
     * null on somebody's screen.
     */
    @Test
    @DisplayName("both codes are minted when the restaurant accepts, and not before")
    void codesAppearWithTheBag() {
        assertThat(slice.getPickupCode()).isEmpty();
        assertThat(order.getDeliveryPin()).isEmpty();

        service.accept(OWNER, SLICE, 20);

        // Numeric so it can be read aloud across a counter, six because that is
        // the length people already type from memory.
        assertThat(slice.getPickupCode()).hasSize(6).containsOnlyDigits();
        assertThat(order.getDeliveryPin()).hasSize(6).containsOnlyDigits();
    }

    /** Re-minting would not be a smaller bug than never minting: it would make a
     *  courier holding the right code wrong. */
    @Test
    void aCodeSomebodyHasAlreadyReadOutIsNeverReplaced() {
        service.accept(OWNER, SLICE, 20);
        String pickup = slice.getPickupCode();
        String pin = order.getDeliveryPin();

        slice.mintPickupCode("000000");
        order.mintDeliveryPin("111111");

        assertThat(slice.getPickupCode()).isEqualTo(pickup);
        assertThat(order.getDeliveryPin()).isEqualTo(pin);
    }

    /** The column holds eight characters. A config row asking for forty digits
     *  must not turn every accept into a failed insert. */
    @Test
    void anAbsurdCodeLengthIsClampedToWhatTheColumnHolds() {
        assertThat(HandoffCodes.numeric(40)).hasSize(8);
        assertThat(HandoffCodes.numeric(1)).hasSize(4);
    }

    // MARK: The counter

    @Test
    void theRightCodeCollectsTheOrder() {
        atTheCounter();

        HandoffResultDto result = service.pickedUp(COURIER_USER, ORDER, slice.getPickupCode());

        assertThat(result.accepted()).isTrue();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.DELIVERING);
    }

    /** A courier reading 482 913 off a screen types the space, and a client that
     *  formats the field sends it. Refusing a correct code over whitespace gets
     *  blamed on the code. */
    @Test
    void aCodeTypedWithSpacesIsStillTheRightCode() {
        atTheCounter();
        String spaced = slice.getPickupCode().substring(0, 3) + " "
            + slice.getPickupCode().substring(3);

        assertThat(service.pickedUp(COURIER_USER, ORDER, spaced).accepted()).isTrue();
    }

    /**
     * The milestone's second decision, tested: a wrong code is an <em>answer</em>.
     * No exception, a 200's worth of result, and a message the courier can act
     * on — which deliberately does not say how wrong they were, because "one
     * digit off" is a shorter guess list.
     */
    @Test
    @DisplayName("a wrong pickup code is an answer, not an error")
    void aWrongPickupCodeIsRefusedWithoutThrowing() {
        atTheCounter();

        HandoffResultDto result = service.pickedUp(COURIER_USER, ORDER, "000000");

        assertThat(result.accepted()).isFalse();
        assertThat(result.message()).doesNotContain(slice.getPickupCode());
        assertThat(order.getStatus()).isEqualTo(OrderStatus.COURIER_TO_RESTAURANT);
        // The job comes back with the refusal: a mistyped digit must not blank
        // the screen telling them where they are.
        assertThat(result.job()).isNotNull();
    }

    @Test
    void aPickupWithNoCodeAsksForOne() {
        atTheCounter();

        HandoffResultDto result = service.pickedUp(COURIER_USER, ORDER, null);

        assertThat(result.accepted()).isFalse();
        assertThat(result.message()).isEqualTo("Ask the restaurant for the pickup code");
    }

    /**
     * The asymmetry with the delivery PIN, and the reason for it. At a counter
     * the merchant is standing right there, so the code is a check rather than a
     * gate — a courier who cannot get past it is a courier locked out of food
     * everybody in the room can see is theirs.
     */
    @Test
    @DisplayName("pickup attempts are never counted and never lock anybody out")
    void aCourierAtACounterCannotFailPermanently() {
        atTheCounter();

        for (int i = 0; i < 10; i++) {
            HandoffResultDto refusal = service.pickedUp(COURIER_USER, ORDER, "000000");
            assertThat(refusal.accepted()).isFalse();
            // -1 means "not counted", which is a different statement from "none
            // left" and the client draws it differently.
            assertThat(refusal.attemptsLeft()).isEqualTo(-1);
            assertThat(refusal.supportUnlocked()).isFalse();
        }
        assertThat(order.getHandoffAttempts()).isZero();
        assertThat(service.pickedUp(COURIER_USER, ORDER, slice.getPickupCode()).accepted()).isTrue();
    }

    /** An order accepted before V38 has no code, and a migration must not
     *  retroactively lock a courier out of a delivery they are already
     *  carrying. */
    @Test
    @DisplayName("an order minted before V38 is collected with no code at all")
    void aPreV38OrderStillCollects() {
        atTheCounter();
        set(slice, "pickupCode", "");

        assertThat(service.pickedUp(COURIER_USER, ORDER, null).accepted()).isTrue();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.DELIVERING);
    }

    // MARK: The door

    @Test
    void theRightPinDeliversAndSettles() {
        atTheDoor();

        HandoffResultDto result = service.delivered(COURIER_USER, ORDER, order.getDeliveryPin());

        assertThat(result.accepted()).isTrue();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.DELIVERED);
        verify(payments).settle(order, java.util.Map.of(MERCHANT, "Forno Nero"));
        verify(dispatch).complete(JobKind.DELIVERY, ORDER, null);
    }

    /**
     * The count, and the moment the fallback opens. Three is the configured
     * maximum, so the third wrong PIN is the one that unlocks support — not the
     * fourth, which would be a courier told "0 left" and then refused anyway.
     */
    @Test
    @DisplayName("wrong PINs count down and unlock the photo fallback at exactly the maximum")
    void aWrongPinCountsUpAndUnlocksAtTheMaximum() {
        atTheDoor();

        HandoffResultDto first = service.delivered(COURIER_USER, ORDER, "000000");
        assertThat(first.accepted()).isFalse();
        assertThat(first.attemptsLeft()).isEqualTo(2);
        assertThat(first.supportUnlocked()).isFalse();

        HandoffResultDto second = service.delivered(COURIER_USER, ORDER, "000000");
        assertThat(second.attemptsLeft()).isEqualTo(1);
        assertThat(second.supportUnlocked()).isFalse();

        HandoffResultDto third = service.delivered(COURIER_USER, ORDER, "000000");
        assertThat(third.attemptsLeft()).isZero();
        assertThat(third.supportUnlocked()).isTrue();
        assertThat(third.message()).containsIgnoringCase("photo");
    }

    /**
     * The one that matters most. A refusal must leave the order exactly where it
     * was — still DELIVERING, because the courier still has the food — and must
     * not touch the hold. Half-settling a delivery that did not happen is the
     * failure this whole milestone exists to prevent.
     */
    @Test
    @DisplayName("a failed handoff moves neither the status nor the money")
    void aRefusalIsInert() {
        atTheDoor();

        service.delivered(COURIER_USER, ORDER, "000000");

        assertThat(order.getStatus()).isEqualTo(OrderStatus.DELIVERING);
        verify(payments, never()).settle(any(), any());
        verify(dispatch, never()).complete(any(), any(), any());
    }

    /** SPECS §5 says a failed PIN leaves the order ARRIVED. There is no such
     *  status and there will not be one: DELIVERING is precisely what an order
     *  with a courier still holding it is. */
    @Test
    void aFailedHandoffInventsNoSeventhStatus() {
        atTheDoor();
        service.delivered(COURIER_USER, ORDER, "000000");
        service.delivered(COURIER_USER, ORDER, "000000");
        service.delivered(COURIER_USER, ORDER, "000000");

        assertThat(order.getStatus()).isEqualTo(OrderStatus.DELIVERING);
    }

    /** A plain confirm is what every order did before this milestone, and what
     *  a customer who wants no ceremony still gets. */
    @Test
    void aConfirmOrderNeedsNothingTyped() {
        atTheDoor();
        order.chooseHandoffMode(HandoffMode.CONFIRM);

        HandoffResultDto result = service.delivered(COURIER_USER, ORDER, null);

        assertThat(result.accepted()).isTrue();
        // Nothing is counted on a confirm, so there is no budget to report.
        assertThat(result.attemptsLeft()).isEqualTo(-1);
        verify(payments).settle(order, java.util.Map.of(MERCHANT, "Forno Nero"));
    }

    /** A PIN order that predates V38 has no PIN to check, and falls back to the
     *  plain confirm rather than to a door nobody can open. */
    @Test
    void aPreV38OrderIsHandedOverOnAPlainConfirm() {
        atTheDoor();
        set(order, "deliveryPin", "");

        assertThat(service.delivered(COURIER_USER, ORDER, null).accepted()).isTrue();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.DELIVERED);
    }

    // MARK: Contactless

    /** "Leave it at the door" has to mean a door somebody photographed. Without
     *  that the mode is a checkbox that turns the check off. */
    @Test
    void contactlessRefusesUntilThereIsActuallyAPhoto() {
        atTheDoor();
        order.chooseHandoffMode(HandoffMode.PHOTO);

        HandoffResultDto result = service.delivered(COURIER_USER, ORDER, null);

        assertThat(result.accepted()).isFalse();
        assertThat(result.message()).isEqualTo("Take a photo of the drop-off first");
        assertThat(order.getStatus()).isEqualTo(OrderStatus.DELIVERING);
        verify(payments, never()).settle(any(), any());
    }

    @Test
    void contactlessCompletesOncePhotographed() {
        atTheDoor();
        order.chooseHandoffMode(HandoffMode.PHOTO);
        presign("private/delivery-proof/" + COURIER_USER + "/one.jpg");
        service.proofPhotoUpload(COURIER_USER, ORDER);

        assertThat(service.delivered(COURIER_USER, ORDER, null).accepted()).isTrue();
        verify(payments).settle(order, java.util.Map.of(MERCHANT, "Forno Nero"));
    }

    /**
     * The fallback, which is the deliberate hole in this milestone: three wrong
     * PINs and a photo will complete a delivery. It can be abused by failing on
     * purpose; the alternative is a courier stranded in the street with food
     * nobody will accept, and the abuse is at least recorded on the row and
     * photographed.
     */
    @Test
    @DisplayName("after the PIN attempts are spent, a photo finishes the delivery")
    void theFallbackUnstrandsACourier() {
        atTheDoor();
        service.delivered(COURIER_USER, ORDER, "000000");
        service.delivered(COURIER_USER, ORDER, "000000");
        service.delivered(COURIER_USER, ORDER, "000000");
        presign("private/delivery-proof/" + COURIER_USER + "/two.jpg");
        service.proofPhotoUpload(COURIER_USER, ORDER);

        HandoffResultDto result = service.delivered(COURIER_USER, ORDER, null);

        assertThat(result.accepted()).isTrue();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.DELIVERED);
        // Never reset: the count is the only record that the fallback was used,
        // and it is what a dispute reads.
        assertThat(order.getHandoffAttempts()).isEqualTo(3);
    }

    /** The fallback is a door that opens after three failures, not one that was
     *  never locked. A photo uploaded early buys nothing. */
    @Test
    void aPhotoDoesNotSkipThePinBeforeTheAttemptsAreSpent() {
        atTheDoor();
        presign("private/delivery-proof/" + COURIER_USER + "/early.jpg");
        service.proofPhotoUpload(COURIER_USER, ORDER);

        HandoffResultDto result = service.delivered(COURIER_USER, ORDER, null);

        assertThat(result.accepted()).isFalse();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.DELIVERING);
    }

    /**
     * A courier at a door nobody is answering has no PIN to type, so an empty
     * submission has to count — otherwise they could never reach the fallback
     * that exists for exactly their situation. Three taps is the honest way out
     * of a silent doorstep.
     */
    @Test
    void anEmptySubmissionIsAWrongPinAndCountsAsOne() {
        atTheDoor();

        HandoffResultDto result = service.delivered(COURIER_USER, ORDER, null);

        assertThat(result.accepted()).isFalse();
        assertThat(result.attemptsLeft()).isEqualTo(2);
        assertThat(result.message()).isEqualTo("Ask them for the PIN on their order screen");
    }

    /** The fallback adds a way through; it does not close the front door. */
    @Test
    void theRightPinStillWorksAfterTheFallbackOpens() {
        atTheDoor();
        service.delivered(COURIER_USER, ORDER, "000000");
        service.delivered(COURIER_USER, ORDER, "000000");
        service.delivered(COURIER_USER, ORDER, "000000");

        assertThat(service.delivered(COURIER_USER, ORDER, order.getDeliveryPin()).accepted())
            .isTrue();
    }

    // MARK: The photo itself

    /**
     * No request anywhere accepts a client-supplied key. The partner document
     * flow presigns and takes a key back on an attach, which needs a prefix
     * check to stop somebody attaching any object in the bucket; here the server
     * stamps the key it just minted, in the same transaction, so there is
     * nothing to check because nothing is asked.
     */
    @Test
    @DisplayName("the server stamps the key it minted, and never takes one from a client")
    void theProofKeyIsTheServersOwn() {
        atTheDoor();
        presign("private/delivery-proof/" + COURIER_USER + "/three.jpg");

        ProofUploadDto upload = service.proofPhotoUpload(COURIER_USER, ORDER);

        verify(privateMedia).presignDocumentUpload(eq(COURIER_USER), eq("delivery-proof"),
            anyString());
        assertThat(order.getProofPhotoKey()).isEqualTo(upload.objectKey());
    }

    /** Nothing sweeps the private prefix — the cleanup job only knows about
     *  public media — so a retaken photo would otherwise leave a picture of a
     *  stranger's front door in the bucket forever. */
    @Test
    void retakingThePhotoDeletesTheOneItReplaces() {
        atTheDoor();
        presign("private/delivery-proof/" + COURIER_USER + "/first.jpg");
        service.proofPhotoUpload(COURIER_USER, ORDER);
        presign("private/delivery-proof/" + COURIER_USER + "/second.jpg");

        service.proofPhotoUpload(COURIER_USER, ORDER);

        verify(privateMedia).deleteDocument("private/delivery-proof/" + COURIER_USER + "/first.jpg");
        assertThat(order.getProofPhotoKey())
            .isEqualTo("private/delivery-proof/" + COURIER_USER + "/second.jpg");
    }

    /** A photo of a doorstep before the food has even been collected is not
     *  proof of anything. */
    @Test
    void aProofPhotoBeforePickupIsRefused() {
        atTheCounter();

        assertThatThrownBy(() -> service.proofPhotoUpload(COURIER_USER, ORDER))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Pick the order up first");
    }

    // MARK: What each screen may see

    /**
     * The whole security model in one assertion. A courier who could read either
     * code off their own job could collect food they are not standing in front
     * of and confirm a delivery they have not made, which is exactly what the
     * codes exist to prevent.
     */
    @Test
    @DisplayName("the courier's job carries neither the pickup code nor the PIN")
    void theCourierSeesNeitherCode() {
        atTheDoor();
        set(slice, "pickupCode", "888888");
        set(order, "deliveryPin", "999999");

        // Taken off a refusal, which is the one response that carries the job
        // back without anything having moved.
        CourierJobDto job = service.delivered(COURIER_USER, ORDER, "000000").job();

        assertThat(job).isNotNull();
        assertThat(job.toString()).doesNotContain("888888").doesNotContain("999999");
    }

    /** The kitchen reads the pickup code aloud, which is what that screen is
     *  for. It has no business knowing the number that confirms the food reached
     *  somebody's door. */
    @Test
    void theKitchenSeesThePickupCodeAndNothingElse() {
        service.accept(OWNER, SLICE, 20);
        set(slice, "pickupCode", "888888");
        set(order, "deliveryPin", "999999");
        when(subOrders.queueFor(eq(MERCHANT), any()))
            .thenReturn(java.util.List.of(slice));

        MerchantOrderDto queued = service.queue(OWNER).getFirst();

        assertThat(queued.pickupCode()).isEqualTo("888888");
        assertThat(queued.toString()).doesNotContain("999999");
    }

    // MARK: The thread

    /**
     * The third consumer of the {@code ConversationContext} seam 2b M3 built —
     * a listing, then a ride, now an order — and it cost the messaging module
     * nothing, which is the entire argument for a generic reference over a
     * {@code listingId} column.
     */
    @Test
    @DisplayName("assignment opens the courier↔customer thread with a card back to the order")
    void theThreadOpensWithAnOrderCard() {
        service.accept(OWNER, SLICE, 20);

        service.courierAssigned(ORDER, assignment());

        ArgumentCaptor<ConversationContext> context =
            ArgumentCaptor.forClass(ConversationContext.class);
        verify(messaging).openDirectConversation(eq(CUSTOMER), eq(COURIER_USER),
            context.capture());
        assertThat(context.getValue().kind()).isEqualTo("order");
        assertThat(context.getValue().refId()).isEqualTo(ORDER.toString());
        assertThat(context.getValue().title()).isEqualTo("Forno Nero");
        assertThat(order.getConversationId()).isEqualTo(CONVERSATION);
    }

    /** {@code RideService}'s posture, copied exactly: a chat that did not open
     *  is an inconvenience, and rolling back an assignment over one would leave
     *  somebody on a bike outside a restaurant that is no longer expecting
     *  them. */
    @Test
    @DisplayName("a chat that won't open never costs a courier their delivery")
    void messagingFailingIsSwallowed() {
        when(messaging.openDirectConversation(any(), any(), any()))
            .thenThrow(new IllegalStateException("dynamo is having a moment"));
        service.accept(OWNER, SLICE, 20);

        service.courierAssigned(ORDER, assignment());

        assertThat(order.getStatus()).isEqualTo(OrderStatus.COURIER_TO_RESTAURANT);
        assertThat(order.getConversationId()).isNull();
    }

    // MARK: Helpers

    /** An accepted order with a courier on their way to collect it. */
    private void atTheCounter() {
        service.accept(OWNER, SLICE, 20);
        service.courierAssigned(ORDER, assignment());
    }

    /** The same, with the food already in the courier's hands. */
    private void atTheDoor() {
        atTheCounter();
        service.pickedUp(COURIER_USER, ORDER, slice.getPickupCode());
    }

    private void presign(String objectKey) {
        when(privateMedia.presignDocumentUpload(any(), anyString(), anyString()))
            .thenReturn(new MediaDocumentApi.DocumentUpload(
                "https://s3.example/" + objectKey + "?sig", objectKey, "image/jpeg", 900));
    }

    private Assignment assignment() {
        return new Assignment(COURIER_WORKER, COURIER_USER, WorkerKind.COURIER,
            VehicleCategory.SCOOTER, JobKind.DELIVERY, ORDER, 4.9, 214,
            new VehicleRef(UUID.randomUUID(), VehicleCategory.SCOOTER,
                "Red Honda scooter", "9911-B-2", false),
            OffsetDateTime.now());
    }

    private static ProfileDto profile() {
        return new ProfileDto(COURIER_USER, "sub", "courier@example.com", "Yassine B.",
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
     *  matches the row V38 seeds, so this is also a test that they do. */
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
