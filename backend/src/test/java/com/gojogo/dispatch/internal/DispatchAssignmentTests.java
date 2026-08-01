package com.gojogo.dispatch.internal;

import com.gojogo.dispatch.DispatchAssigned;
import com.gojogo.dispatch.JobKind;
import com.gojogo.dispatch.VehicleCategory;
import com.gojogo.dispatch.WorkerKind;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.web.server.ResponseStatusException;

import java.lang.reflect.Field;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * What happens when somebody takes a job — and, mostly, what happens to everybody
 * who didn't.
 *
 * <p>Two people each believing an order is theirs is the one failure this module
 * exists to prevent, so the races are the tests worth having: the second accept
 * on the same job, the accept that arrives after the offer lapsed, and the
 * difference between losing a race and ignoring your phone, which must not read
 * the same on a driver's record.
 */
class DispatchAssignmentTests {

    private static final UUID DRIVER_USER = UUID.randomUUID();
    private static final UUID RIVAL_USER = UUID.randomUUID();
    private static final UUID RIDE = UUID.randomUUID();

    private WorkerRepository workers;
    private DispatchJobRepository jobs;
    private OfferRepository offers;
    private DispatchService service;
    private List<Object> published;

    private Worker driver;
    private Worker rival;
    private DispatchJob job;
    private Offer driverOffer;
    private Offer rivalOffer;

    @BeforeEach
    void setUp() {
        workers = mock(WorkerRepository.class);
        jobs = mock(DispatchJobRepository.class);
        offers = mock(OfferRepository.class);
        published = new ArrayList<>();
        ApplicationEventPublisher events = mock(ApplicationEventPublisher.class);
        org.mockito.Mockito.doAnswer(call -> published.add(call.getArgument(0)))
            .when(events).publishEvent(any(Object.class));

        DispatchPolicy policy = mock(DispatchPolicy.class);
        when(policy.waveRadiiKm()).thenReturn(List.of(1.0, 3.0, 7.0));
        when(policy.waveIntervalSeconds()).thenReturn(15L);
        when(policy.waveSize()).thenReturn(5);
        when(policy.offerTtlSeconds()).thenReturn(30L);
        when(policy.requestTtlSeconds()).thenReturn(300L);
        when(policy.ranking()).thenReturn(
            new CandidateRanker.Policy(60, 0, 900, 60, 25, 15));

        service = new DispatchService(workers, jobs, offers, policy, List.of(), events);

        driver = worker(DRIVER_USER, WorkerKind.DRIVER);
        rival = worker(RIVAL_USER, WorkerKind.DRIVER);
        job = new DispatchJob(JobKind.RIDE, RIDE, UUID.randomUUID(), WorkerKind.DRIVER,
            EnumSet.of(VehicleCategory.CAR), 33.57, -7.58, "Bd Anfa", null, null, "", "",
            OffsetDateTime.now(), OffsetDateTime.now().plusMinutes(5));
        setId(job, UUID.randomUUID());
        driverOffer = offer(job, driver, OffsetDateTime.now().plusSeconds(30));
        rivalOffer = offer(job, rival, OffsetDateTime.now().plusSeconds(30));

        when(jobs.findById(job.getId())).thenReturn(Optional.of(job));
        when(jobs.findByJobKindAndJobRefId(JobKind.RIDE, RIDE)).thenReturn(Optional.of(job));
        when(offers.findById(driverOffer.getId())).thenReturn(Optional.of(driverOffer));
        when(offers.findById(rivalOffer.getId())).thenReturn(Optional.of(rivalOffer));
        when(workers.findById(driver.getId())).thenReturn(Optional.of(driver));
        when(workers.findById(rival.getId())).thenReturn(Optional.of(rival));
        when(workers.findByUserIdOrderByKindAsc(DRIVER_USER)).thenReturn(List.of(driver));
        when(workers.findByUserIdOrderByKindAsc(RIVAL_USER)).thenReturn(List.of(rival));
        when(offers.findByJobIdAndState(job.getId(), OfferState.OFFERED))
            .thenAnswer(call -> openOffers());
    }

    @Test
    @DisplayName("accepting assigns the job, makes the worker busy, and tells the vertical")
    void acceptAssigns() {
        AssignmentDto assignment = service.accept(DRIVER_USER, driverOffer.getId());

        assertThat(assignment.jobRefId()).isEqualTo(RIDE);
        assertThat(job.getState()).isEqualTo(JobState.ASSIGNED);
        assertThat(job.getAssignedWorkerId()).isEqualTo(driver.getId());
        assertThat(driver.getStatus()).isEqualTo(WorkerStatus.BUSY);
        assertThat(driverOffer.getState()).isEqualTo(OfferState.ACCEPTED);
        assertThat(published).singleElement().isInstanceOf(DispatchAssigned.class);
    }

    @Test
    @DisplayName("everybody else's offer is withdrawn, not expired — they lost a race "
        + "nobody told them they were in")
    void losersAreWithdrawnNotExpired() {
        service.accept(DRIVER_USER, driverOffer.getId());

        assertThat(rivalOffer.getState()).isEqualTo(OfferState.WITHDRAWN);
        // The distinction is the whole point: a withdrawal must not read as
        // "ignored their phone" on an acceptance rate.
        assertThat(rival.getExpiredCount()).isZero();
        assertThat(rival.getDeclinedCount()).isZero();
    }

    @Test
    @DisplayName("the second accept on the same job is refused, and says so plainly")
    void secondAcceptIsRefused() {
        service.accept(DRIVER_USER, driverOffer.getId());

        assertThatThrownBy(() -> service.accept(RIVAL_USER, rivalOffer.getId()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Somebody else took that one");
        assertThat(job.getAssignedWorkerId()).isEqualTo(driver.getId());
        assertThat(rival.getStatus()).isEqualTo(WorkerStatus.AVAILABLE);
    }

    @Test
    @DisplayName("two accepts a millisecond apart: the database is the arbiter, not "
        + "the state check")
    void optimisticLockDecidesTheRace() {
        // Both callers passed the in-memory check; only one survives the version
        // column. Without this the loser would silently overwrite the winner.
        doThrow(new OptimisticLockingFailureException("version"))
            .when(jobs).saveAndFlush(any(DispatchJob.class));

        assertThatThrownBy(() -> service.accept(DRIVER_USER, driverOffer.getId()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Somebody else took that one");
        assertThat(published).isEmpty();
    }

    @Test
    @DisplayName("an offer accepted a second too late is expired, and counts as ignored")
    void lapsedOfferCannotBeAccepted() {
        Offer stale = offer(job, driver, OffsetDateTime.now().minusSeconds(1));
        when(offers.findById(stale.getId())).thenReturn(Optional.of(stale));

        assertThatThrownBy(() -> service.accept(DRIVER_USER, stale.getId()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("expired");
        assertThat(stale.getState()).isEqualTo(OfferState.EXPIRED);
        assertThat(driver.getExpiredCount()).isEqualTo(1);
        assertThat(job.getState()).isEqualTo(JobState.SEARCHING);
    }

    @Test
    @DisplayName("somebody else's offer is a 404, not a 403 — it is not theirs to "
        + "learn about")
    void anotherWorkersOfferIsInvisible() {
        assertThatThrownBy(() -> service.accept(RIVAL_USER, driverOffer.getId()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("No such offer");
    }

    @Test
    @DisplayName("declining counts once; declining again is not an error")
    void decliningIsIdempotent() {
        service.decline(DRIVER_USER, driverOffer.getId());
        service.decline(DRIVER_USER, driverOffer.getId());

        assertThat(driverOffer.getState()).isEqualTo(OfferState.DECLINED);
        assertThat(driver.getDeclinedCount()).isEqualTo(1);
    }

    @Test
    @DisplayName("one person, one pair of hands: accepting as a driver makes their "
        + "courier registration busy too")
    void dualModeGoesBusyEverywhere() {
        Worker asCourier = worker(DRIVER_USER, WorkerKind.COURIER);
        when(workers.findByUserIdOrderByKindAsc(DRIVER_USER))
            .thenReturn(List.of(driver, asCourier));

        service.accept(DRIVER_USER, driverOffer.getId());

        assertThat(asCourier.getStatus()).isEqualTo(WorkerStatus.BUSY);
    }

    @Test
    @DisplayName("completing frees every registration, and the first real rating "
        + "replaces the placeholder rather than averaging with it")
    void completingReleasesAndRates() {
        service.accept(DRIVER_USER, driverOffer.getId());

        service.complete(JobKind.RIDE, RIDE, 4);

        assertThat(driver.getStatus()).isEqualTo(WorkerStatus.AVAILABLE);
        assertThat(driver.getCompletedCount()).isEqualTo(1);
        // The 5.00 a new worker is created with is display, not a rating anybody
        // gave them — counting it would hand every driver a free five stars.
        assertThat(driver.getRating()).isEqualByComparingTo("4.00");
        assertThat(driver.getRatingCount()).isEqualTo(1);
    }

    @Test
    @DisplayName("later ratings are a running mean")
    void ratingsAverage() {
        driver.countCompleted(4);
        driver.countCompleted(5);
        driver.countCompleted(3);

        assertThat(driver.getRating()).isEqualByComparingTo("4.00");
        assertThat(driver.getRatingCount()).isEqualTo(3);
    }

    @Test
    @DisplayName("an unrated job is not a five-star one")
    void completingWithoutARatingDoesNotInventOne() {
        service.accept(DRIVER_USER, driverOffer.getId());

        service.complete(JobKind.RIDE, RIDE, null);

        assertThat(driver.getCompletedCount()).isEqualTo(1);
        assertThat(driver.getRatingCount()).isZero();
    }

    @Test
    @DisplayName("cancelling frees the worker, and only counts against them when the "
        + "caller says it was their fault")
    void cancellingCountsOnlyWhenAtFault() {
        service.accept(DRIVER_USER, driverOffer.getId());

        service.cancel(JobKind.RIDE, RIDE, false);

        assertThat(job.getState()).isEqualTo(JobState.CANCELLED);
        assertThat(job.getAssignedWorkerId()).isNull();
        assertThat(driver.getStatus()).isEqualTo(WorkerStatus.AVAILABLE);
        assertThat(driver.getCancelledCount()).isZero();
    }

    @Test
    @DisplayName("a driver who drove off does have it counted")
    void workerFaultCancellationCounts() {
        service.accept(DRIVER_USER, driverOffer.getId());

        service.cancel(JobKind.RIDE, RIDE, true);

        assertThat(driver.getCancelledCount()).isEqualTo(1);
    }

    @Test
    @DisplayName("cancelling something dispatch never heard of is a no-op, not a 404")
    void cancellingAnUnknownJobIsSafe() {
        when(jobs.findByJobKindAndJobRefId(JobKind.DELIVERY, RIDE)).thenReturn(Optional.empty());

        service.cancel(JobKind.DELIVERY, RIDE, false);
    }

    @Test
    @DisplayName("asking twice for the same job finds the search already running")
    void requestIsIdempotent() {
        UUID first = service.request(new com.gojogo.dispatch.DispatchRequest(JobKind.RIDE, RIDE,
            WorkerKind.DRIVER, EnumSet.of(VehicleCategory.CAR), UUID.randomUUID(),
            33.57, -7.58, "Bd Anfa", null, null, "", "", null));

        assertThat(first).isEqualTo(job.getId());
        // Nothing was saved: offering one trip to two sets of drivers is a bug
        // that stays invisible until two of them arrive.
        org.mockito.Mockito.verify(jobs, org.mockito.Mockito.never())
            .saveAndFlush(any(DispatchJob.class));
    }

    @Test
    @DisplayName("a suspended worker cannot put themselves back on the road")
    void suspendedCannotGoAvailable() {
        driver.setSuspended(true);
        when(workers.findByUserIdAndKind(DRIVER_USER, WorkerKind.DRIVER))
            .thenReturn(Optional.of(driver));

        assertThatThrownBy(() -> service.setAvailability(DRIVER_USER, WorkerKind.DRIVER, true))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("suspended");
        assertThat(driver.getStatus()).isEqualTo(WorkerStatus.OFFLINE);
    }

    @Test
    @DisplayName("signing off withdraws whatever was on screen")
    void signingOffWithdrawsOpenOffers() {
        when(workers.findByUserIdAndKind(DRIVER_USER, WorkerKind.DRIVER))
            .thenReturn(Optional.of(driver));
        when(offers.findByWorkerIdAndStateOrderByOfferedAtAsc(driver.getId(), OfferState.OFFERED))
            .thenReturn(List.of(driverOffer));

        service.setAvailability(DRIVER_USER, WorkerKind.DRIVER, false);

        assertThat(driver.getStatus()).isEqualTo(WorkerStatus.OFFLINE);
        assertThat(driverOffer.getState()).isEqualTo(OfferState.WITHDRAWN);
    }

    @Test
    @DisplayName("a worker mid-job cannot toggle their way out of it")
    void busyWorkersStayBusy() {
        driver.markBusy();
        when(workers.findByUserIdAndKind(DRIVER_USER, WorkerKind.DRIVER))
            .thenReturn(Optional.of(driver));

        service.setAvailability(DRIVER_USER, WorkerKind.DRIVER, false);

        // Abandoning somebody standing on a pavement is a cancellation, with a
        // caller who owns it — not a switch.
        assertThat(driver.getStatus()).isEqualTo(WorkerStatus.BUSY);
    }

    @Test
    @DisplayName("a position is written to every registration the person holds")
    void positionsFanOutAcrossRegistrations() {
        Worker asCourier = worker(DRIVER_USER, WorkerKind.COURIER);
        when(workers.findByUserIdOrderByKindAsc(DRIVER_USER))
            .thenReturn(List.of(driver, asCourier));

        service.reportPosition(DRIVER_USER, 33.6, -7.6);

        assertThat(driver.getLatitude()).isEqualTo(33.6);
        assertThat(asCourier.getLatitude()).isEqualTo(33.6);
    }

    @Test
    @DisplayName("an empty category list means anything, not nothing")
    void unspecifiedCategoriesMatchEverything() {
        DispatchJob anyVehicle = new DispatchJob(JobKind.DELIVERY, UUID.randomUUID(), null,
            WorkerKind.COURIER, EnumSet.noneOf(VehicleCategory.class), 0, 0, "", null, null,
            "", "", OffsetDateTime.now(), OffsetDateTime.now().plusMinutes(5));

        assertThat(anyVehicle.categories()).containsAll(EnumSet.allOf(VehicleCategory.class));
    }

    @Test
    @DisplayName("a stored category this build no longer knows is skipped, not thrown on")
    void unknownStoredCategoriesAreSkipped() {
        DispatchJob stored = new DispatchJob(JobKind.RIDE, UUID.randomUUID(), null,
            WorkerKind.DRIVER, EnumSet.of(VehicleCategory.CAR), 0, 0, "", null, null, "", "",
            OffsetDateTime.now(), OffsetDateTime.now().plusMinutes(5));
        set(stored, "categories", "CAR,HOVERCRAFT");

        // A row outlives the enum that wrote it; a rollback must not make old
        // jobs unreadable.
        assertThat(stored.categories()).containsExactly(VehicleCategory.CAR);
    }

    // MARK: Fixtures

    private List<Offer> openOffers() {
        return List.of(driverOffer, rivalOffer).stream()
            .filter(o -> o.getState() == OfferState.OFFERED)
            .toList();
    }

    private static Worker worker(UUID userId, WorkerKind kind) {
        Worker worker = new Worker(userId, kind, UUID.randomUUID(), VehicleCategory.CAR,
            "Casa", "White Dacia Logan", "12345-A-6");
        setId(worker, UUID.randomUUID());
        worker.reportPosition(33.57, -7.58);
        worker.setAvailable(true);
        return worker;
    }

    private static Offer offer(DispatchJob job, Worker worker, OffsetDateTime expiresAt) {
        Offer offer = new Offer(job.getId(), worker.getId(), 1, expiresAt);
        setId(offer, UUID.randomUUID());
        return offer;
    }

    /** Entity ids are database-generated; these tests never reach one. */
    private static void setId(Object entity, UUID id) {
        set(entity, "id", id);
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
