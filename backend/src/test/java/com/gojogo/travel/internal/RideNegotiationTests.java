package com.gojogo.travel.internal;

import com.gojogo.dispatch.Assignment;
import com.gojogo.dispatch.DispatchApi;
import com.gojogo.dispatch.JobKind;
import com.gojogo.dispatch.VehicleCategory;
import com.gojogo.dispatch.WorkerKind;
import com.gojogo.messaging.MessagingApi;
import com.gojogo.payments.InsufficientFundsException;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.WalletApi;
import com.gojogo.profile.ProfileApi;
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
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Haggling, and the ways it must not go wrong.
 *
 * <p>Negotiation is the one thing a ride has that a delivery order does not, and
 * almost every failure it can have is silent: a driver bidding on a trip nobody
 * offered them, two live prices from the same person, a counter accepted a second
 * after somebody else took the job. None of those throws on its own — they are
 * all "a plausible thing happened and the wrong person got the trip".
 */
class RideNegotiationTests {

    private static final UUID RIDER = UUID.randomUUID();
    private static final UUID DRIVER = UUID.randomUUID();
    private static final UUID RIVAL = UUID.randomUUID();
    private static final UUID WORKER = UUID.randomUUID();
    private static final UUID RIVAL_WORKER = UUID.randomUUID();
    private static final com.gojogo.dispatch.VehicleRef CAR = new com.gojogo.dispatch.VehicleRef(
        UUID.randomUUID(), VehicleCategory.CAR, "White Dacia Logan", "12345-A-6", false);

    private RideRepository rides;
    private RideOfferRepository offers;
    private DispatchApi dispatch;
    private WalletApi wallet;
    private MessagingApi messaging;
    private RideTokenService rideTokens;
    private RideService service;
    private Ride ride;

    @BeforeEach
    void setUp() {
        rides = mock(RideRepository.class);
        offers = mock(RideOfferRepository.class);
        PricingConfigRepository pricing = mock(PricingConfigRepository.class);
        dispatch = mock(DispatchApi.class);
        wallet = mock(WalletApi.class);
        messaging = mock(MessagingApi.class);
        ProfileApi profiles = mock(ProfileApi.class);
        ApplicationEventPublisher events = mock(ApplicationEventPublisher.class);

        TravelPolicy policy = mock(TravelPolicy.class);
        when(policy.maxRounds()).thenReturn(2);
        when(policy.offerTtlSeconds()).thenReturn(45L);
        when(policy.requestTtlSeconds()).thenReturn(300L);
        when(policy.cancelFeeMinor()).thenReturn(200L);
        when(policy.ratingWindowDays()).thenReturn(7L);
        when(policy.maxOfferMultipleBps()).thenReturn(30_000L);

        when(wallet.currency()).thenReturn("USD");
        when(wallet.balancesOf(any(), any()))
            .thenReturn(new WalletApi.Balances("USD", 100_000, 0, 0, 0, 0));
        when(wallet.transfer(any(), any(), anyLong(), any(), any(), anyString()))
            .thenReturn(new WalletApi.Movement(UUID.randomUUID(), 0, false));
        when(profiles.findById(any())).thenReturn(Optional.empty());
        when(pricing.inForce(anyString(), any(), any()))
            .thenReturn(List.of(pricingRow()));
        when(offers.save(any())).thenAnswer(call -> {
            RideOffer saved = call.getArgument(0);
            if (idOf(saved) == null) set(saved, "id", UUID.randomUUID());
            return saved;
        });
        when(rides.saveAndFlush(any())).thenAnswer(call -> call.getArgument(0));

        rideTokens = mock(RideTokenService.class);
        service = new RideService(rides, offers, pricing, policy, dispatch, wallet,
            rideTokens, messaging, profiles, mock(com.gojogo.share.ShareApi.class), events);

        ride = new Ride(RIDER, "CAR", 33.5731, -7.5898, "Bd Anfa",
            33.5892, -7.6031, "Maarif", "", 4_000, 600, 1_000, 900, "USD",
            OffsetDateTime.now().plusMinutes(5));
        set(ride, "id", UUID.randomUUID());
        when(rides.findById(ride.getId())).thenReturn(Optional.of(ride));
        when(dispatch.offeredWorkerId(JobKind.RIDE, ride.getId(), DRIVER))
            .thenReturn(Optional.of(WORKER));
        when(dispatch.offeredWorkerId(JobKind.RIDE, ride.getId(), RIVAL))
            .thenReturn(Optional.of(RIVAL_WORKER));
        when(dispatch.assign(any(), any(), any())).thenAnswer(call ->
            new Assignment(call.getArgument(2), DRIVER, WorkerKind.DRIVER, VehicleCategory.CAR,
                JobKind.RIDE, ride.getId(), 4.8, 120, CAR, OffsetDateTime.now()));
        when(offers.findByRideIdAndState(any(), any())).thenReturn(List.of());
        when(offers.findByRideIdAndDriverWorkerIdOrderByCreatedAtAsc(any(), any()))
            .thenReturn(List.of());
    }

    // MARK: Who may bid

    @Test
    @DisplayName("a driver nobody offered the trip to cannot bid on it")
    void onlyOfferedDriversMayCounter() {
        UUID stranger = UUID.randomUUID();
        when(dispatch.offeredWorkerId(JobKind.RIDE, ride.getId(), stranger))
            .thenReturn(Optional.empty());

        // Otherwise every driver in the city could bid on every ride, and
        // dispatch's whole candidate search would be decorative.
        assertThatThrownBy(() -> service.counter(stranger, ride.getId(), 1_200))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("wasn't offered to you");
    }

    @Test
    @DisplayName("a driver's second price replaces their first rather than sitting beside it")
    void aSecondCounterWithdrawsTheFirst() {
        RideOffer first = offer(OfferParty.DRIVER, 1_200, 1);
        when(offers.findByRideIdAndDriverWorkerIdOrderByCreatedAtAsc(ride.getId(), WORKER))
            .thenReturn(List.of(first));

        service.counter(DRIVER, ride.getId(), 1_100);

        // Two live prices from one person would let them be accepted at
        // whichever the rider tapped — that is not a negotiation, it is a trap.
        assertThat(first.getState()).isEqualTo(RideOfferState.WITHDRAWN);
    }

    @Test
    @DisplayName("haggling stops at the round cap")
    void roundsAreCapped() {
        when(offers.findByRideIdAndDriverWorkerIdOrderByCreatedAtAsc(ride.getId(), WORKER))
            .thenReturn(List.of(offer(OfferParty.DRIVER, 1_200, 1),
                offer(OfferParty.RIDER, 1_000, 2)));

        assertThatThrownBy(() -> service.counter(DRIVER, ride.getId(), 1_150))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("had your say");
    }

    @Test
    @DisplayName("a counter puts the ride into NEGOTIATING")
    void counteringOpensTheConversation() {
        service.counter(DRIVER, ride.getId(), 1_200);

        assertThat(ride.getState()).isEqualTo(RideState.NEGOTIATING);
    }

    @Test
    @DisplayName("nobody may accept their own price")
    void youCannotAcceptYourOwnOffer() {
        RideOffer mine = offer(OfferParty.RIDER, 1_000, 2);
        when(offers.findById(mine.getId())).thenReturn(Optional.of(mine));

        assertThatThrownBy(() -> service.acceptAsRider(RIDER, ride.getId(), mine.getId()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("your own price");
    }

    // MARK: Tokens (Phase 3 M4)

    @Test
    @DisplayName("confirming charges the driver's tokens and freezes what they cost")
    void confirmingChargesTokens() {
        when(rideTokens.charge(any())).thenReturn(2);
        RideOffer theirs = offer(OfferParty.DRIVER, 1_200, 1);
        when(offers.findById(theirs.getId())).thenReturn(Optional.of(theirs));

        service.acceptAsRider(RIDER, ride.getId(), theirs.getId());

        // Frozen onto the row, like the fare and for the same reason: it is what
        // a cancellation gives back, and a price list that moves afterwards must
        // not change it.
        assertThat(ride.getTokenCost()).isEqualTo(2);
        verify(rideTokens).charge(ride);
    }

    @Test
    @DisplayName("a cancelled trip gives the tokens back")
    void cancellingRefundsTokens() {
        when(rideTokens.charge(any())).thenReturn(2);
        RideOffer theirs = offer(OfferParty.DRIVER, 1_200, 1);
        when(offers.findById(theirs.getId())).thenReturn(Optional.of(theirs));
        service.acceptAsRider(RIDER, ride.getId(), theirs.getId());

        service.cancel(RIDER, ride.getId(), "changed my mind");

        verify(rideTokens).refund(ride);
    }

    @Test
    @DisplayName("a completed trip keeps them — that is what they bought")
    void completingKeepsTokens() {
        when(rideTokens.charge(any())).thenReturn(2);
        RideOffer theirs = offer(OfferParty.DRIVER, 1_200, 1);
        when(offers.findById(theirs.getId())).thenReturn(Optional.of(theirs));
        service.acceptAsRider(RIDER, ride.getId(), theirs.getId());
        service.startTrip(DRIVER, ride.getId());

        service.complete(DRIVER, ride.getId());

        verify(rideTokens, never()).refund(any());
    }

    // MARK: Settling

    @Test
    @DisplayName("accepting a driver's price confirms the ride at that price, not the "
        + "one the rider first asked at")
    void acceptingFreezesTheAgreedFare() {
        RideOffer theirs = offer(OfferParty.DRIVER, 1_200, 1);
        when(offers.findById(theirs.getId())).thenReturn(Optional.of(theirs));

        service.acceptAsRider(RIDER, ride.getId(), theirs.getId());

        assertThat(ride.getState()).isEqualTo(RideState.CONFIRMED);
        assertThat(ride.getAgreedFareMinor()).isEqualTo(1_200);
        // The other two are kept, because "you charged 12 when the app said 10"
        // is a question somebody will ask.
        assertThat(ride.getSuggestedFareMinor()).isEqualTo(1_000);
        assertThat(ride.getOfferedFareMinor()).isEqualTo(900);
        assertThat(theirs.getState()).isEqualTo(RideOfferState.ACCEPTED);
        assertThat(ride.getVehiclePlate()).isEqualTo("12345-A-6");
    }

    @Test
    @DisplayName("dispatch is asked before anything is written, so losing the race "
        + "leaves the ride untouched")
    void dispatchRefusalLeavesNothingBehind() {
        RideOffer theirs = offer(OfferParty.DRIVER, 1_200, 1);
        when(offers.findById(theirs.getId())).thenReturn(Optional.of(theirs));
        doThrow(new ResponseStatusException(HttpStatus.CONFLICT, "Somebody else took that one"))
            .when(dispatch).assign(any(), any(), any());

        assertThatThrownBy(() -> service.acceptAsRider(RIDER, ride.getId(), theirs.getId()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Somebody else took");
        assertThat(ride.getState()).isEqualTo(RideState.REQUESTED);
        assertThat(ride.getAgreedFareMinor()).isNull();
        // And crucially the offer is still live: the rider can take a different
        // one rather than having burned this driver's price on a lost race.
        assertThat(theirs.getState()).isEqualTo(RideOfferState.PENDING);
    }

    @Test
    @DisplayName("every other price is withdrawn the moment one is taken")
    void othersAreWithdrawnOnConfirmation() {
        RideOffer taken = offer(OfferParty.DRIVER, 1_200, 1);
        RideOffer alsoOnTheTable = offer(OfferParty.DRIVER, 1_400, 1);
        when(offers.findById(taken.getId())).thenReturn(Optional.of(taken));
        when(offers.findByRideIdAndState(ride.getId(), RideOfferState.PENDING))
            .thenReturn(List.of(taken, alsoOnTheTable));

        service.acceptAsRider(RIDER, ride.getId(), taken.getId());

        assertThat(alsoOnTheTable.getState()).isEqualTo(RideOfferState.WITHDRAWN);
    }

    @Test
    @DisplayName("a price that lapsed under the rider's thumb cannot be taken")
    void lapsedOffersCannotBeAccepted() {
        RideOffer stale = offer(OfferParty.DRIVER, 1_200, 1);
        set(stale, "expiresAt", OffsetDateTime.now().minusSeconds(1));
        when(offers.findById(stale.getId())).thenReturn(Optional.of(stale));

        assertThatThrownBy(() -> service.acceptAsRider(RIDER, ride.getId(), stale.getId()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("expired");
        assertThat(stale.getState()).isEqualTo(RideOfferState.EXPIRED);
        assertThat(ride.getState()).isEqualTo(RideState.REQUESTED);
    }

    @Test
    @DisplayName("a rider who cannot cover the price is stopped before a driver is "
        + "committed to it")
    void anEmptyWalletRefusesTheAccept() {
        RideOffer theirs = offer(OfferParty.DRIVER, 1_200, 1);
        when(offers.findById(theirs.getId())).thenReturn(Optional.of(theirs));
        when(wallet.balancesOf(any(), eq(RIDER)))
            .thenReturn(new WalletApi.Balances("USD", 300, 0, 0, 0, 0));

        assertThatThrownBy(() -> service.acceptAsRider(RIDER, ride.getId(), theirs.getId()))
            .isInstanceOf(InsufficientFundsException.class);
        verify(dispatch, never()).assign(any(), any(), any());
    }

    // MARK: The trip and the money

    @Test
    @DisplayName("the driver keeps the whole fare — rides carry no commission")
    void completionPaysTheDriverInFull() {
        confirmAt(1_200);
        ride.markArriving();
        ride.start();

        service.complete(DRIVER, ride.getId());

        verify(wallet).transfer(any(), any(), eq(1_200L), eq(LedgerKind.RIDE_FARE),
            any(), eq("ride:" + ride.getId() + ":fare"));
        assertThat(ride.getState()).isEqualTo(RideState.COMPLETED);
    }

    @Test
    @DisplayName("cancelling before the driver moved is free")
    void cancellingEarlyCostsNothing() {
        confirmAt(1_200);

        service.cancel(RIDER, ride.getId(), "changed my mind");

        assertThat(ride.getCancelFeeMinor()).isZero();
        verify(wallet, never()).transfer(any(), any(), anyLong(), any(), any(), anyString());
    }

    @Test
    @DisplayName("cancelling once they're on the way pays the driver, not the platform")
    void cancellingLatePaysTheDriver() {
        confirmAt(1_200);
        ride.markArriving();

        service.cancel(RIDER, ride.getId(), null);

        assertThat(ride.getCancelFeeMinor()).isEqualTo(200);
        verify(wallet).transfer(any(), any(), eq(200L), eq(LedgerKind.RIDE_FARE),
            any(), eq("ride:" + ride.getId() + ":cancelfee"));
    }

    @Test
    @DisplayName("an empty wallet waives the cancellation fee rather than trapping "
        + "the rider in the ride")
    void anUnpayableFeeIsWaived() {
        confirmAt(1_200);
        ride.markArriving();
        doThrow(new InsufficientFundsException(200, 0, "USD"))
            .when(wallet).transfer(any(), any(), anyLong(), any(), any(), anyString());

        service.cancel(RIDER, ride.getId(), null);

        assertThat(ride.getState()).isEqualTo(RideState.CANCELLED_RIDER);
        assertThat(ride.getCancelFeeMinor()).isZero();
    }

    @Test
    @DisplayName("a trip in progress is ended, not cancelled")
    void aLiveTripCannotBeCancelled() {
        confirmAt(1_200);
        ride.markArriving();
        ride.start();

        assertThatThrownBy(() -> service.cancel(RIDER, ride.getId(), null))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("end it instead");
    }

    // MARK: Ratings

    @Test
    @DisplayName("neither side sees the other's rating until both are in")
    void ratingsAreBlindUntilBothAreIn() {
        confirmAt(1_200);
        ride.markArriving();
        ride.start();
        ride.complete();

        RideDto afterRider = service.rate(RIDER, ride.getId(), 5);
        assertThat(afterRider.myRating()).isEqualTo(5);
        // A driver who could read a one-star before writing their own is being
        // invited to answer it.
        assertThat(afterRider.theirRating()).isNull();

        RideDto afterBoth = service.rate(DRIVER, ride.getId(), 3);
        assertThat(afterBoth.theirRating()).isNotNull();
    }

    @Test
    @DisplayName("rating twice is refused, and an unfinished trip cannot be rated")
    void ratingIsOncePerSide() {
        confirmAt(1_200);
        assertThatThrownBy(() -> service.rate(RIDER, ride.getId(), 5))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("finished trip");

        ride.markArriving();
        ride.start();
        ride.complete();
        service.rate(RIDER, ride.getId(), 5);

        assertThatThrownBy(() -> service.rate(RIDER, ride.getId(), 1))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("already rated");
    }

    @Test
    @DisplayName("the rider's stars go to the driver's dispatch rating, which is what "
        + "matching filters on")
    void ratingTheDriverFeedsDispatch() {
        confirmAt(1_200);
        ride.markArriving();
        ride.start();
        ride.complete();

        service.rate(RIDER, ride.getId(), 4);

        verify(dispatch).complete(JobKind.RIDE, ride.getId(), 4);
    }

    // MARK: Fixtures

    private void confirmAt(long fareMinor) {
        ride.confirm(WORKER, DRIVER, CAR, fareMinor);
    }

    private RideOffer offer(OfferParty party, long amount, int round) {
        RideOffer offer = new RideOffer(ride.getId(), WORKER, DRIVER, party, amount, round,
            OffsetDateTime.now().plusSeconds(45));
        set(offer, "id", UUID.randomUUID());
        return offer;
    }

    private static PricingConfig pricingRow() {
        PricingConfig config = new PricingConfig();
        set(config, "category", "CAR");
        set(config, "baseMinor", 200L);
        set(config, "perKmMinor", 120L);
        set(config, "perMinuteMinor", 15L);
        set(config, "minimumMinor", 500L);
        set(config, "surgeBps", 10_000);
        return config;
    }

    private static UUID idOf(RideOffer offer) {
        return offer.getId();
    }

    private static void set(Object entity, String field, Object value) {
        try {
            Field f = entity.getClass().getDeclaredField(field);
            f.setAccessible(true);
            f.set(entity, value);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }
}
