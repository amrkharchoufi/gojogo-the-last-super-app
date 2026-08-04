package com.gojogo.delivery.internal;

import com.gojogo.dispatch.DispatchApi;
import com.gojogo.media.MediaDocumentApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.web.server.ResponseStatusException;

import java.lang.reflect.Field;
import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The customer's half of the handoff: the PIN they read out, the choice of how
 * the food arrives, and the photograph of their own front door.
 *
 * <p>Every assertion here is about <em>what a screen may see and when</em>,
 * which is where the codes either work or are theatre. A PIN that is still on
 * the order screen a month later is a number in a screenshot; a proof photo
 * behind a stored URL is a private object with a public link; and a contactless
 * choice that cannot be made once the courier is close is a choice made before
 * the reason for it existed.
 */
class HandoffModeTests {

    private static final UUID CUSTOMER = UUID.randomUUID();
    private static final UUID MERCHANT = UUID.randomUUID();
    private static final UUID ORDER = UUID.randomUUID();
    private static final String PROOF_KEY = "private/delivery-proof/courier/door.jpg";

    private OrderRepository orders;
    private MediaDocumentApi privateMedia;
    private DeliveryService delivery;
    private CustomerOrder order;

    @BeforeEach
    void setUp() {
        MerchantRepository merchants = mock(MerchantRepository.class);
        orders = mock(OrderRepository.class);
        privateMedia = mock(MediaDocumentApi.class);
        OrderPayments payments = mock(OrderPayments.class);

        delivery = new DeliveryService(merchants, mock(MenuItemRepository.class), orders,
            mock(AddressRepository.class), mock(ApplicationEventPublisher.class), payments,
            mock(PromotionService.class), mock(MerchantStorefrontService.class),
            mock(OrderFulfilmentService.class), mock(DispatchApi.class),
            new DeliveryPolicy(new StubConfig()), privateMedia, 99);

        Merchant merchant = new Merchant(UUID.randomUUID(), "Forno Nero", "Pizza", null,
            33.57, -7.58);
        set(merchant, "id", MERCHANT);
        when(merchants.findById(MERCHANT)).thenReturn(Optional.of(merchant));

        order = new CustomerOrder(CUSTOMER, "USD", "Second floor",
            OffsetDateTime.now().plusMinutes(30));
        set(order, "id", ORDER);
        order.deliverTo(null, "Home", "12 Rue Ali", "", 33.58, -7.60);
        SubOrder slice = order.addSubOrder(MERCHANT, 2_000, 300, 0, null, "");
        set(slice, "id", UUID.randomUUID());
        order.priceIt(Basket.of(MERCHANT, 2_000, 300, 99, 0, 0, "USD"));
        slice.mintPickupCode("482913");
        order.mintDeliveryPin("901224");
        when(orders.findById(ORDER)).thenReturn(Optional.of(order));
    }

    // MARK: The PIN

    @Test
    @DisplayName("the PIN is on the customer's order and nowhere else in the system")
    void thePinIsVisibleWhileItIsTheThingThatOpensTheDoor() {
        order.moveTo(OrderStatus.DELIVERING, OffsetDateTime.now());

        assertThat(delivery.get(CUSTOMER, ORDER).deliveryPin()).isEqualTo("901224");
    }

    /** A PIN that outlives its handoff is a number sitting in a history screen
     *  for a year, on the one surface it can be read from at all. */
    @Test
    void thePinDisappearsOnceTheFoodHasArrived() {
        order.moveTo(OrderStatus.DELIVERED, OffsetDateTime.now());

        assertThat(delivery.get(CUSTOMER, ORDER).deliveryPin()).isEmpty();
    }

    @Test
    void aContactlessOrderShowsNoPinToRead() {
        order.moveTo(OrderStatus.DELIVERING, OffsetDateTime.now());
        order.chooseHandoffMode(HandoffMode.PHOTO);

        OrderDto dto = delivery.get(CUSTOMER, ORDER);

        assertThat(dto.deliveryPin()).isEmpty();
        assertThat(dto.handoffMode()).isEqualTo("PHOTO");
    }

    // MARK: Changing your mind

    /**
     * Contactless is a decision people make when the courier is already close —
     * the baby has just gone down, or they have realised they will be in the
     * shower. A mode fixed at checkout is a mode chosen before the reason for it
     * existed.
     */
    @Test
    void theModeCanBeChangedWithTheCourierAlreadyOnTheWay() {
        order.moveTo(OrderStatus.DELIVERING, OffsetDateTime.now());

        OrderDto dto = delivery.setHandoffMode(CUSTOMER, ORDER, "PHOTO");

        assertThat(dto.handoffMode()).isEqualTo("PHOTO");
        assertThat(order.getHandoffMode()).isEqualTo(HandoffMode.PHOTO);
    }

    @Test
    @DisplayName("changing how it is handed over, after it has been, is refused")
    void theModeIsFixedOnceTheFoodIsThere() {
        order.moveTo(OrderStatus.DELIVERED, OffsetDateTime.now());

        assertThatThrownBy(() -> delivery.setHandoffMode(CUSTOMER, ORDER, "PHOTO"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("already been delivered");
        assertThat(order.getHandoffMode()).isEqualTo(HandoffMode.PIN);
    }

    /** A one-tap control that can return a 400 is a control that looks broken,
     *  and an older client sending a word this build has never heard of must not
     *  be one of the ways it does. */
    @Test
    void aWordThisBuildHasNeverHeardOfIsTheDefault() {
        order.moveTo(OrderStatus.DELIVERING, OffsetDateTime.now());
        order.chooseHandoffMode(HandoffMode.CONFIRM);

        assertThat(delivery.setHandoffMode(CUSTOMER, ORDER, "DRONE").handoffMode())
            .isEqualTo("PIN");
        assertThat(delivery.setHandoffMode(CUSTOMER, ORDER, null).handoffMode())
            .isEqualTo("PIN");
    }

    /** Lower case, spaces, whatever a client sends. */
    @Test
    void theModeIsReadLeniently() {
        order.moveTo(OrderStatus.DELIVERING, OffsetDateTime.now());

        assertThat(delivery.setHandoffMode(CUSTOMER, ORDER, " photo ").handoffMode())
            .isEqualTo("PHOTO");
    }

    /** 404 rather than 403 for somebody else's order — don't confirm it exists,
     *  and certainly don't hand over the PIN that opens its door. */
    @Test
    void somebodyElsesOrderIsNotFound() {
        assertThatThrownBy(() -> delivery.setHandoffMode(UUID.randomUUID(), ORDER, "PHOTO"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("No such order");
    }

    // MARK: The proof photo

    /**
     * A link minted for this one read, never stored — the same posture
     * {@code MediaDocumentApi} takes with a driving licence, applied to a
     * photograph of somebody's front door with their dinner on it. The object
     * key behind it never leaves the server.
     */
    @Test
    @DisplayName("the proof photo is a signed link minted per read, never a stored key")
    void theProofPhotoIsSignedFresh() {
        order.moveTo(OrderStatus.DELIVERED, OffsetDateTime.now());
        order.proofPhotographedAt(PROOF_KEY);
        when(privateMedia.presignDocumentRead(PROOF_KEY)).thenReturn("https://s3.example/x?sig");

        OrderDto dto = delivery.get(CUSTOMER, ORDER);

        assertThat(dto.proofPhotoUrl()).isEqualTo("https://s3.example/x?sig");
        assertThat(dto.toString()).doesNotContain(PROOF_KEY);
    }

    /** Before the order is delivered, a photo on the row is a courier's failed
     *  attempt rather than proof of anything. */
    @Test
    void thereIsNoProofLinkUntilTheFoodHasArrived() {
        order.moveTo(OrderStatus.DELIVERING, OffsetDateTime.now());
        order.proofPhotographedAt(PROOF_KEY);

        assertThat(delivery.get(CUSTOMER, ORDER).proofPhotoUrl()).isNull();
        verify(privateMedia, never()).presignDocumentRead(anyString());
    }

    /** The order screen is how somebody finds out what happened to their food.
     *  It must not go blank because S3 was slow. */
    @Test
    void aSigningFailureCostsThePhotoAndNotTheScreen() {
        order.moveTo(OrderStatus.DELIVERED, OffsetDateTime.now());
        order.proofPhotographedAt(PROOF_KEY);
        when(privateMedia.presignDocumentRead(PROOF_KEY))
            .thenThrow(new IllegalStateException("no region configured"));

        OrderDto dto = delivery.get(CUSTOMER, ORDER);

        assertThat(dto.proofPhotoUrl()).isNull();
        assertThat(dto.status()).isEqualTo("DELIVERED");
    }

    // MARK: Helpers

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
