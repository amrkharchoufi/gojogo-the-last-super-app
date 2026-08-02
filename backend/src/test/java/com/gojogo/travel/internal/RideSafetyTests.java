package com.gojogo.travel.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.dispatch.DispatchApi;
import com.gojogo.dispatch.VehicleCategory;
import com.gojogo.dispatch.VehicleRef;
import com.gojogo.dispatch.WorkerPosition;
import com.gojogo.messaging.MessagingApi;
import com.gojogo.payments.WalletApi;
import com.gojogo.profile.EmergencyContactDto;
import com.gojogo.profile.ProfileApi;
import com.gojogo.share.ShareApi;
import com.gojogo.share.ShareableResource;
import com.gojogo.travel.SosRaised;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.web.server.ResponseStatusException;

import java.lang.reflect.Field;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * SOS and trip sharing (SPECS §10).
 *
 * <p>Two rules are worth failing a build over. <b>The flag survives everything
 * else</b> — an alarm that is lost because a link could not be minted is an
 * alarm nobody ever sees. And <b>the shared payload is thin</b>: whoever holds
 * the URL sees it, so a full name or a handle leaking into it is a privacy bug
 * shipped to the public internet.
 */
class RideSafetyTests {

    private static final UUID RIDER = UUID.randomUUID();
    private static final UUID DRIVER = UUID.randomUUID();
    private static final UUID WORKER = UUID.randomUUID();
    private static final VehicleRef CAR = new VehicleRef(UUID.randomUUID(), VehicleCategory.CAR,
        "White Dacia Logan", "12345-A-6", true);

    private RideRepository rides;
    private ShareApi share;
    private ProfileApi profiles;
    private ApplicationEventPublisher events;
    private RideService service;
    private Ride ride;

    @BeforeEach
    void setUp() {
        rides = mock(RideRepository.class);
        share = mock(ShareApi.class);
        profiles = mock(ProfileApi.class);
        events = mock(ApplicationEventPublisher.class);
        WalletApi wallet = mock(WalletApi.class);
        DispatchApi dispatch = mock(DispatchApi.class);

        TravelPolicy policy = mock(TravelPolicy.class);
        when(policy.shareTtlMinutes()).thenReturn(180L);
        when(policy.shareGraceMinutes()).thenReturn(60L);
        when(policy.emergencyNumber()).thenReturn("112");
        when(wallet.currency()).thenReturn("USD");
        when(profiles.findById(any())).thenReturn(Optional.empty());
        when(profiles.emergencyContactsOf(any())).thenReturn(List.of());
        when(share.mint(anyString(), any(), any(), any(), any())).thenAnswer(call ->
            new ShareApi.SharedLink(UUID.randomUUID(), "tok", "https://gojogo.app/s/tok",
                call.getArgument(0), call.getArgument(1), call.getArgument(3),
                OffsetDateTime.now().plusHours(3), 0));

        service = new RideService(rides, mock(RideOfferRepository.class),
            mock(PricingConfigRepository.class), policy, dispatch, wallet,
            mock(RideTokenService.class), mock(MessagingApi.class), profiles, share, events);

        ride = new Ride(RIDER, "CAR", 33.5731, -7.5898, "Bd Anfa",
            33.5892, -7.6031, "Maarif", "", 4_000, 600, 1_000, 900, "USD",
            OffsetDateTime.now().plusMinutes(5));
        set(ride, "id", UUID.randomUUID());
        when(rides.findById(ride.getId())).thenReturn(Optional.of(ride));
    }

    // MARK: SOS

    @Test
    @DisplayName("SOS flags the trip, mints a link and hands back a number to dial")
    void sosFlagsAndReturnsTheNumber() {
        live();

        SosDto sos = service.raiseSos(RIDER, ride.getId());

        assertThat(ride.hasSos()).isTrue();
        assertThat(ride.getSosBy()).isEqualTo(RIDER);
        assertThat(sos.emergencyNumber()).isEqualTo("112");
        assertThat(sos.shareUrl()).isEqualTo("https://gojogo.app/s/tok");
        assertThat(sos.message()).contains("https://gojogo.app/s/tok");
    }

    @Test
    @DisplayName("the flag is written before anything else can fail")
    void theFlagSurvivesAFailedMint() {
        live();
        when(share.mint(anyString(), any(), any(), any(), any()))
            .thenThrow(new IllegalStateException("share is down"));

        assertThatThrownBy(() -> service.raiseSos(RIDER, ride.getId()))
            .isInstanceOf(IllegalStateException.class);

        // The row was flushed first, on purpose: an alarm lost to a downstream
        // outage is an alarm nobody ever sees.
        assertThat(ride.hasSos()).isTrue();
    }

    @Test
    @DisplayName("the driver can raise one too — nights are not only dangerous for riders")
    void eitherPartyMayRaiseIt() {
        live();

        service.raiseSos(DRIVER, ride.getId());

        assertThat(ride.getSosBy()).isEqualTo(DRIVER);
    }

    @Test
    @DisplayName("a stranger's trip is a 404, not a 403")
    void strangersCannotRaiseOne() {
        live();

        assertThatThrownBy(() -> service.raiseSos(UUID.randomUUID(), ride.getId()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("404");
        assertThat(ride.hasSos()).isFalse();
    }

    @Test
    @DisplayName("only the contacts who are also on GojoGo are counted as notified")
    void onlyLinkedContactsArePushed() {
        live();
        when(profiles.emergencyContactsOf(RIDER)).thenReturn(List.of(
            new EmergencyContactDto(UUID.randomUUID(), "Mum", "+212600000000", "Family", null),
            new EmergencyContactDto(UUID.randomUUID(), "Sara", "+212600000001", "Friend",
                DRIVER)));

        SosDto sos = service.raiseSos(RIDER, ride.getId());

        assertThat(sos.contacts()).hasSize(2);
        assertThat(sos.notifiedCount()).isEqualTo(1);
        ArgumentCaptor<Object> published = ArgumentCaptor.forClass(Object.class);
        verify(events).publishEvent(published.capture());
        assertThat(((SosRaised) published.getValue()).contactProfileIds())
            .containsExactly(DRIVER);
    }

    @Test
    @DisplayName("raising it twice keeps the first time — an SOS is not re-datable")
    void sosIsRecordedOnce() {
        live();
        service.raiseSos(RIDER, ride.getId());
        OffsetDateTime first = ride.getSosAt();

        service.raiseSos(RIDER, ride.getId());

        assertThat(ride.getSosAt()).isEqualTo(first);
    }

    @Test
    @DisplayName("a finished trip refuses, and says to call the number instead")
    void finishedTripsRefuse() {
        live();
        ride.complete();

        assertThatThrownBy(() -> service.raiseSos(RIDER, ride.getId()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("emergency number");
    }

    // MARK: Sharing

    @Test
    @DisplayName("a live trip can be shared, with the message already written")
    void shareALiveTrip() {
        live();

        ShareTripDto shared = service.shareTrip(RIDER, ride.getId());

        assertThat(shared.url()).isEqualTo("https://gojogo.app/s/tok");
        assertThat(shared.message()).contains("Maarif").contains(shared.url());
    }

    @Test
    @DisplayName("a trip nobody has taken yet cannot be shared — there is nothing to watch")
    void cannotShareBeforeAMatch() {
        assertThatThrownBy(() -> service.shareTrip(RIDER, ride.getId()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("409");
        verify(share, never()).mint(anyString(), any(), any(), any(), any());
    }

    @Test
    @DisplayName("the link outlives a long trip rather than a flat clock")
    void ttlFollowsTheTrip() {
        set(ride, "durationSeconds", 4 * 60 * 60); // a four-hour drive
        live();

        service.shareTrip(RIDER, ride.getId());

        ArgumentCaptor<Duration> ttl = ArgumentCaptor.forClass(Duration.class);
        verify(share).mint(anyString(), any(), any(), any(), ttl.capture());
        assertThat(ttl.getValue()).isEqualTo(Duration.ofMinutes(4 * 60 + 60));
    }

    // MARK: What a stranger sees

    @Test
    @DisplayName("the public view carries a plate and a first name, and nothing else")
    void publicViewIsThin() {
        live();
        ride.start();
        DispatchApi dispatch = mock(DispatchApi.class);
        when(dispatch.positionOf(WORKER)).thenReturn(Optional.of(
            new WorkerPosition(WORKER, DRIVER, 33.58, -7.60, OffsetDateTime.now())));
        ProfileApi named = mock(ProfileApi.class);
        when(named.findById(RIDER)).thenReturn(Optional.of(profile("Sara El Amrani", "sara")));
        when(named.findById(DRIVER)).thenReturn(Optional.of(profile("Amina Benali", "amina")));
        ConfigApi config = mock(ConfigApi.class);
        when(config.number(anyString(), anyLong()))
            .thenAnswer(call -> call.getArgument(1, Long.class));

        ShareableResource.SharedView view =
            new RideShareableResource(rides, dispatch, named, config)
                .render(ride.getId()).orElseThrow();

        assertThat(view.headline()).contains("Sara").contains("Amina").doesNotContain("Benali");
        assertThat(view.detail()).contains("12345-A-6");
        assertThat(view.latitude()).isEqualTo(33.58);
        assertThat(view.finished()).isFalse();
        // Nothing anywhere in the payload that could be used to reach either of
        // them, or to find them in the app.
        assertThat(view.toString()).doesNotContain("@").doesNotContain(RIDER.toString());
    }

    @Test
    @DisplayName("a link stops resolving once the trip is long over")
    void oldTripsStopResolving() {
        live();
        ride.complete();
        set(ride, "completedAt", OffsetDateTime.now().minusHours(3));
        ConfigApi config = mock(ConfigApi.class);
        when(config.number(anyString(), anyLong()))
            .thenAnswer(call -> call.getArgument(1, Long.class));

        Optional<ShareableResource.SharedView> view =
            new RideShareableResource(rides, mock(DispatchApi.class), profiles, config)
                .render(ride.getId());

        assertThat(view).isEmpty();
    }

    @Test
    @DisplayName("a trip that just ended still resolves, so the watcher sees the arrival")
    void justFinishedTripsStillResolve() {
        live();
        ride.complete();
        ConfigApi config = mock(ConfigApi.class);
        when(config.number(anyString(), anyLong()))
            .thenAnswer(call -> call.getArgument(1, Long.class));

        ShareableResource.SharedView view =
            new RideShareableResource(rides, mock(DispatchApi.class), profiles, config)
                .render(ride.getId()).orElseThrow();

        assertThat(view.status()).isEqualTo("Arrived safely");
        assertThat(view.finished()).isTrue();
        assertThat(view.latitude()).isNull();
    }

    // MARK: Fixtures

    private void live() {
        ride.confirm(WORKER, DRIVER, CAR, 900);
    }

    private static com.gojogo.profile.ProfileDto profile(String name, String handle) {
        return new com.gojogo.profile.ProfileDto(UUID.randomUUID(), "sub-" + handle,
            handle + "@example.com", name, handle, "", "", null, null, java.util.Set.of(),
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
}
