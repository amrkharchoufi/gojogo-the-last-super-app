package com.gojogo.travel.internal;

import com.gojogo.dispatch.JobKind;
import com.gojogo.payments.InsufficientFundsException;
import com.gojogo.payments.TokenApi;
import com.gojogo.payments.WalletApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Field;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
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
 * Charging a driver for a job, and the ways that must not go wrong.
 *
 * <p>Two of these are the milestone's whole risk. A charge that <em>refuses a
 * confirmation</em> would kill a trip the rider has already been promised over
 * the driver's balance; a cancellation that keeps the tokens would make
 * cancelling a source of revenue. Neither shows up as an error — both are just a
 * number that is quietly wrong, in the direction that favours the platform.
 */
class RideTokenChargeTests {

    private static final UUID DRIVER = UUID.randomUUID();
    private static final UUID RIDER = UUID.randomUUID();

    private RideTokenPriceRepository prices;
    private TokenApi tokens;
    private RideTokenService service;
    private Ride ride;

    @BeforeEach
    void setUp() {
        prices = mock(RideTokenPriceRepository.class);
        tokens = mock(TokenApi.class);
        when(tokens.spend(any(), anyLong(), any(), anyString()))
            .thenReturn(new WalletApi.Movement(UUID.randomUUID(), 0, false));
        when(tokens.refund(any(), anyLong(), any(), anyString()))
            .thenReturn(new WalletApi.Movement(UUID.randomUUID(), 0, false));
        when(prices.inForce(anyString(), any())).thenReturn(List.of());
        when(prices.inForce(eq("CAR"), any())).thenReturn(carPrices());

        service = new RideTokenService(prices, tokens);
        ride = confirmedRide(4_000);
    }

    // MARK: The charge

    @Test
    @DisplayName("a confirmed ride costs its band, once, keyed on the ride")
    void chargesTheBand() {
        assertThat(service.charge(ride)).isEqualTo(2);
        verify(tokens).spend(eq(DRIVER), eq(2L), any(), eq("ride:" + ride.getId() + ":tokens"));
    }

    @Test
    @DisplayName("a driver who can't pay still gets the trip")
    void anEmptyBalanceDoesNotUnwindTheRide() {
        doThrow(new InsufficientFundsException(200, 0, "USD"))
            .when(tokens).spend(any(), anyLong(), any(), anyString());

        // The rider has been told a car is coming. Refusing here would take it
        // away from them over somebody else's balance — and eligibility already
        // stops this happening at the point it can be stopped harmlessly.
        assertThat(service.charge(ride)).isZero();
    }

    @Test
    @DisplayName("a free category writes no ledger entry at all")
    void zeroTokensIsNotAMovement() {
        when(prices.inForce(eq("CAR"), any()))
            .thenReturn(List.of(price("CAR", 2_000_000_000, 0, OffsetDateTime.now())));

        assertThat(service.charge(ride)).isZero();
        verify(tokens, never()).spend(any(), anyLong(), any(), anyString());
    }

    // MARK: The refund

    @Test
    @DisplayName("a cancelled trip returns its tokens whoever cancelled")
    void tokensFollowTheTripNotTheFault() {
        ride.recordTokenCost(2);

        service.refund(ride);

        // SPECS §4 refunds only on driver fault. That would charge a driver for a
        // rider's change of mind and make a cancellation earn the platform money.
        verify(tokens).refund(eq(DRIVER), eq(2L), any(),
            eq("ride:" + ride.getId() + ":tokens:refund"));
    }

    @Test
    @DisplayName("a ride that never charged anything refunds nothing")
    void nothingChargedNothingBack() {
        service.refund(ride);
        verify(tokens, never()).refund(any(), anyLong(), any(), anyString());
    }

    // MARK: Price list reads

    @Test
    @DisplayName("only the newest generation of a price list is in force")
    void generationsDoNotMix() {
        OffsetDateTime old = OffsetDateTime.now().minusDays(30);
        OffsetDateTime now = OffsetDateTime.now().minusMinutes(1);
        // Newest first, the way the query returns them: mixing the two would
        // produce a price list nobody ever wrote.
        when(prices.inForce(eq("CAR"), any())).thenReturn(List.of(
            price("CAR", 3_000, 3, now),
            price("CAR", 2_000_000_000, 6, now),
            price("CAR", 3_000, 1, old),
            price("CAR", 2_000_000_000, 4, old)));

        assertThat(service.costOf(confirmedRide(1_000))).isEqualTo(3);
        assertThat(service.costOf(confirmedRide(50_000))).isEqualTo(6);
    }

    @Test
    @DisplayName("the cheapest ride ignores categories nobody priced")
    void cheapestSkipsUnpricedCategories() {
        // Only CAR has rows; the other five would each read as free, and a
        // "cheapest ride costs 0" would tell every driver they can work.
        assertThat(service.cheapestRide()).isEqualTo(1);
    }

    // MARK: Eligibility (the dispatch SPI)

    @Test
    @DisplayName("a driver short of the fare for this trip is not offered it")
    void tooFewTokensIsARefusal() {
        RideRepository rides = mock(RideRepository.class);
        when(rides.findById(ride.getId())).thenReturn(Optional.of(ride));
        when(tokens.balanceOf(DRIVER)).thenReturn(1L);
        TokenEligibility eligibility = new TokenEligibility(rides, service, tokens);

        assertThat(eligibility.refuseOffer(JobKind.RIDE, ride.getId(), DRIVER))
            .contains("needs 2 tokens");

        when(tokens.balanceOf(DRIVER)).thenReturn(2L);
        assertThat(eligibility.refuseOffer(JobKind.RIDE, ride.getId(), DRIVER)).isNull();
    }

    @Test
    @DisplayName("travel has no opinion about a delivery, or about a job it can't see")
    void vetoesOnlyWhatItPrices() {
        RideRepository rides = mock(RideRepository.class);
        when(rides.findById(any())).thenReturn(Optional.empty());
        when(tokens.balanceOf(any())).thenReturn(0L);
        TokenEligibility eligibility = new TokenEligibility(rides, service, tokens);

        // A courier's delivery is not this module's business, and refusing work
        // we cannot price would turn a bug elsewhere into drivers getting nothing.
        assertThat(eligibility.refuseOffer(JobKind.DELIVERY, UUID.randomUUID(), DRIVER)).isNull();
        assertThat(eligibility.refuseOffer(JobKind.RIDE, UUID.randomUUID(), DRIVER)).isNull();
    }

    @Test
    @DisplayName("an empty balance is explained in words, because dispatch explains nothing")
    void theRefusalIsSayable() {
        when(tokens.balanceOf(DRIVER)).thenReturn(0L);
        assertThat(service.refusalFor(DRIVER)).contains("out of ride tokens");

        when(tokens.balanceOf(DRIVER)).thenReturn(5L);
        assertThat(service.refusalFor(DRIVER)).isNull();
    }

    // MARK: Fixtures

    private static List<RideTokenPrice> carPrices() {
        OffsetDateTime from = OffsetDateTime.now().minusDays(1);
        return List.of(price("CAR", 3_000, 1, from),
            price("CAR", 10_000, 2, from),
            price("CAR", 2_000_000_000, 4, from));
    }

    private static RideTokenPrice price(String category, int upTo, int tokens,
                                        OffsetDateTime from) {
        RideTokenPrice row = new RideTokenPrice();
        set(row, "category", category);
        set(row, "upToMetres", upTo);
        set(row, "tokens", tokens);
        set(row, "effectiveFrom", from);
        return row;
    }

    private static Ride confirmedRide(long metres) {
        Ride ride = new Ride(RIDER, "CAR", 33.5731, -7.5898, "Bd Anfa",
            33.5892, -7.6031, "Maarif", "", metres, 600, 1_000, 900, "USD",
            OffsetDateTime.now().plusMinutes(5));
        set(ride, "id", UUID.randomUUID());
        set(ride, "driverUserId", DRIVER);
        return ride;
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
