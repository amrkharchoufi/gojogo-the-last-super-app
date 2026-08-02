package com.gojogo.partner.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.partner.VehicleVerificationInvited;
import com.gojogo.payments.AccountRef;
import com.gojogo.payments.Bucket;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.WalletApi;
import com.gojogo.profile.ProfileApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.web.server.ResponseStatusException;

import java.lang.reflect.Field;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Community vehicle verification — the passengers check the car (SPECS §4).
 *
 * <p>The tests that matter are the ones about <em>who gets asked</em> and
 * <em>what one "no" does</em>. Everything else is bookkeeping. A mechanism that
 * asks every passenger produces a badge meaning "somebody eventually said yes",
 * and a mechanism that treats four-out-of-five as a pass produces one meaning
 * nothing at all.
 */
class VehicleVerificationTests {

    private static final UUID DRIVER = UUID.randomUUID();
    private static final UUID PASSENGER = UUID.randomUUID();
    private static final UUID RIDE = UUID.randomUUID();

    private VehicleVerificationRepository verifications;
    private VehicleRepository vehicles;
    private PartnerAccountRepository accounts;
    private PartnerService partners;
    private WalletApi wallet;
    private ApplicationEventPublisher events;
    private VehicleVerificationService service;

    private Vehicle vehicle;
    private PartnerAccount account;
    private final List<VehicleVerification> stored = new ArrayList<>();

    @BeforeEach
    void setUp() {
        verifications = mock(VehicleVerificationRepository.class);
        vehicles = mock(VehicleRepository.class);
        accounts = mock(PartnerAccountRepository.class);
        partners = mock(PartnerService.class);
        wallet = mock(WalletApi.class);
        events = mock(ApplicationEventPublisher.class);
        ProfileApi profiles = mock(ProfileApi.class);
        ConfigApi config = mock(ConfigApi.class);
        when(config.number(anyString(), anyLong()))
            .thenAnswer(call -> call.getArgument(1, Long.class));
        when(wallet.currency()).thenReturn("USD");
        when(profiles.findById(any())).thenReturn(Optional.empty());

        account = new PartnerAccount(DRIVER, PartnerKind.DRIVER, "Amina drives");
        set(account, "id", UUID.randomUUID());
        account.approve(UUID.randomUUID(), OffsetDateTime.now());
        // A live stake with the ID check already taken out of it — the state a
        // driver is actually in when their first trip finishes.
        account.recordStakePaid(3000, OffsetDateTime.now());
        account.recordKycFeePaid(500, OffsetDateTime.now());

        vehicle = new Vehicle(account.getId(), DRIVER, "CAR");
        set(vehicle, "id", UUID.randomUUID());
        vehicle.apply("CAR", "Dacia", "Logan", 2021, "White", "12345-A-6", "MA", "Casablanca",
            null, null);
        vehicle.approve("Papers look right");

        when(vehicles.findById(vehicle.getId())).thenReturn(Optional.of(vehicle));
        when(accounts.findById(account.getId())).thenReturn(Optional.of(account));
        when(verifications.findByVehicleIdOrderByCreatedAtDesc(vehicle.getId()))
            .thenAnswer(call -> List.copyOf(stored));
        when(verifications.saveAndFlush(any())).thenAnswer(call -> {
            VehicleVerification saved = call.getArgument(0);
            set(saved, "id", UUID.randomUUID());
            stored.add(saved);
            return saved;
        });
        when(verifications.findById(any())).thenAnswer(call -> stored.stream()
            .filter(v -> call.getArgument(0).equals(idOf(v)))
            .findFirst());

        service = new VehicleVerificationService(verifications, vehicles, accounts, partners,
            wallet, profiles, config, events);
    }

    // MARK: Who gets asked

    @Test
    @DisplayName("the first trip in an approved-but-unverified car asks its passenger")
    void invitesOnFirstTrip() {
        service.inviteFromTrip(RIDE, PASSENGER, DRIVER, vehicle.getId());

        assertThat(stored).hasSize(1);
        ArgumentCaptor<Object> published = ArgumentCaptor.forClass(Object.class);
        verify(events).publishEvent(published.capture());
        assertThat(published.getValue()).isInstanceOf(VehicleVerificationInvited.class);
        VehicleVerificationInvited invite = (VehicleVerificationInvited) published.getValue();
        assertThat(invite.passengerId()).isEqualTo(PASSENGER);
        assertThat(invite.rewardMinor()).isEqualTo(300);
    }

    @Test
    @DisplayName("a car that already has the badge is never asked about again")
    void skipsAlreadyVerified() {
        vehicle.markCommunityVerified();

        service.inviteFromTrip(RIDE, PASSENGER, DRIVER, vehicle.getId());

        assertThat(stored).isEmpty();
    }

    @Test
    @DisplayName("only one invitation is out at a time — the second trip waits")
    void oneLiveInvitationAtATime() {
        service.inviteFromTrip(RIDE, PASSENGER, DRIVER, vehicle.getId());
        service.inviteFromTrip(UUID.randomUUID(), UUID.randomUUID(), DRIVER, vehicle.getId());

        assertThat(stored).hasSize(1);
    }

    @Test
    @DisplayName("a lapsed invitation falls through to the next trip's passenger")
    void fallsThroughAfterExpiry() {
        service.inviteFromTrip(RIDE, PASSENGER, DRIVER, vehicle.getId());
        stored.get(0).expire();

        service.inviteFromTrip(UUID.randomUUID(), UUID.randomUUID(), DRIVER, vehicle.getId());

        assertThat(stored).hasSize(2);
    }

    @Test
    @DisplayName("after three attempts the car stops asking — it simply stays APPROVED")
    void capsAtThreeInvites() {
        for (int i = 0; i < 4; i++) {
            service.inviteFromTrip(UUID.randomUUID(), UUID.randomUUID(), DRIVER,
                vehicle.getId());
            stored.stream().filter(v -> v.getStatus() == VerificationStatus.PENDING)
                .forEach(VehicleVerification::expire);
        }

        assertThat(stored).hasSize(3);
        assertThat(vehicle.getState()).isEqualTo(VehicleState.APPROVED);
    }

    @Test
    @DisplayName("the same passenger is never asked twice about the same car")
    void neverAsksTheSamePassengerTwice() {
        service.inviteFromTrip(RIDE, PASSENGER, DRIVER, vehicle.getId());
        stored.get(0).expire();

        service.inviteFromTrip(UUID.randomUUID(), PASSENGER, DRIVER, vehicle.getId());

        assertThat(stored).hasSize(1);
    }

    @Test
    @DisplayName("a driver cannot verify their own car")
    void driverCannotVerifyThemselves() {
        service.inviteFromTrip(RIDE, DRIVER, DRIVER, vehicle.getId());

        assertThat(stored).isEmpty();
    }

    @Test
    @DisplayName("a trip with no recorded vehicle asks nobody")
    void noVehicleNoInvitation() {
        service.inviteFromTrip(RIDE, PASSENGER, DRIVER, null);

        assertThat(stored).isEmpty();
    }

    // MARK: The answer

    @Test
    @DisplayName("all five yesses earn the badge and pay the passenger from the stake")
    void allYesVerifiesAndPays() {
        service.inviteFromTrip(RIDE, PASSENGER, DRIVER, vehicle.getId());

        service.answer(PASSENGER, idOf(stored.get(0)), yes(null));

        assertThat(vehicle.getState()).isEqualTo(VehicleState.COMMUNITY_VERIFIED);
        verify(wallet).transfer(eq(AccountRef.user(DRIVER, Bucket.STAKING)),
            eq(AccountRef.user(PASSENGER, Bucket.REWARDS)), eq(300L), eq(LedgerKind.REWARD),
            any(), anyString());
        // And the badge is pushed down to dispatch, or it is a badge nobody sees.
        verify(partners).pushVehicleToDispatch(account);
        assertThat(account.getRewardPaidMinor()).isEqualTo(300);
        assertThat(account.remainingStakeMinor()).isEqualTo(3000 - 500 - 300);
    }

    @Test
    @DisplayName("one 'no' flags the car and takes its driver off the road")
    void oneNoFlagsAndSuspends() {
        service.inviteFromTrip(RIDE, PASSENGER, DRIVER, vehicle.getId());

        service.answer(PASSENGER, idOf(stored.get(0)),
            new AnswerVerificationRequest(true, true, false, true, true, "Plate was different"));

        assertThat(vehicle.getState()).isEqualTo(VehicleState.FLAGGED);
        assertThat(vehicle.isActive()).isFalse();
        verify(partners).suspendForVehicle(eq(account), anyString());
        // No reward for a rejection: the money is the driver's until somebody
        // confirms their car, and a complaint is not a confirmation.
        verify(wallet, never()).transfer(any(), any(), anyLong(), any(), any(), anyString());
    }

    @Test
    @DisplayName("a missing answer counts as a no — an older client can't verify by omission")
    void missingAnswerIsNotAYes() {
        service.inviteFromTrip(RIDE, PASSENGER, DRIVER, vehicle.getId());

        service.answer(PASSENGER, idOf(stored.get(0)),
            new AnswerVerificationRequest(true, true, true, true, null, null));

        assertThat(vehicle.getState()).isEqualTo(VehicleState.FLAGGED);
    }

    @Test
    @DisplayName("the reward is capped at what is left of the stake, never a debt")
    void rewardCappedAtRemainingStake() {
        account.recordKycFeePaid(2900, OffsetDateTime.now()); // 3000 - 500 - 2900 → 0 left
        service.inviteFromTrip(RIDE, PASSENGER, DRIVER, vehicle.getId());

        service.answer(PASSENGER, idOf(stored.get(0)), yes(null));

        assertThat(vehicle.getState()).isEqualTo(VehicleState.COMMUNITY_VERIFIED);
        verify(wallet, never()).transfer(any(), any(), anyLong(), any(), any(), anyString());
    }

    @Test
    @DisplayName("somebody else's invitation is a 404, not a 403")
    void anotherPassengersInvitationIsInvisible() {
        service.inviteFromTrip(RIDE, PASSENGER, DRIVER, vehicle.getId());
        UUID id = idOf(stored.get(0));

        assertThatThrownBy(() -> service.answer(UUID.randomUUID(), id, yes(null)))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("404");
    }

    @Test
    @DisplayName("answering twice is refused rather than paying twice")
    void cannotAnswerTwice() {
        service.inviteFromTrip(RIDE, PASSENGER, DRIVER, vehicle.getId());
        UUID id = idOf(stored.get(0));
        service.answer(PASSENGER, id, yes(null));

        assertThatThrownBy(() -> service.answer(PASSENGER, id, yes(null)))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("409");
    }

    // MARK: Fixtures

    private static AnswerVerificationRequest yes(String comment) {
        return new AnswerVerificationRequest(true, true, true, true, true, comment);
    }

    private static UUID idOf(VehicleVerification verification) {
        return verification.getId();
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
}
