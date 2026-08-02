package com.gojogo.dispatch.internal;

import com.gojogo.dispatch.Assignment;
import com.gojogo.dispatch.DispatchApi;
import com.gojogo.dispatch.DispatchAssigned;
import com.gojogo.dispatch.DispatchExhausted;
import com.gojogo.dispatch.DispatchOffered;
import com.gojogo.dispatch.DispatchRequest;
import com.gojogo.dispatch.JobKind;
import com.gojogo.dispatch.VehicleCategory;
import com.gojogo.dispatch.VehicleRef;
import com.gojogo.dispatch.WorkerEligibility;
import com.gojogo.dispatch.WorkerKind;
import com.gojogo.dispatch.WorkerPosition;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Finding somebody, and only that.
 *
 * <p>Three verbs of consequence live here — a vertical asks, workers are offered,
 * one of them accepts — and the whole module is arranged so the third is
 * unambiguous. Two people each believing a job is theirs is the failure this
 * module exists to prevent, so acceptance goes through an optimistic lock on the
 * job row and every loser is told plainly rather than quietly overwritten.
 *
 * <p>The matching itself is deliberately not in here: {@link CandidateRanker} is
 * a pure function over a shortlist, because nothing on the build machine can
 * execute SQL and "who should get this trip" is the last logic in the system that
 * should first run in production.
 */
@Service
class DispatchService implements DispatchApi {

    private static final Logger log = LoggerFactory.getLogger(DispatchService.class);

    /** How wide the database prefilter may go before Java measures. A ring of
     *  7 km in a dense city is a shortlist, not a scan. */
    private static final int SHORTLIST_LIMIT = 500;

    private final WorkerRepository workers;
    private final DispatchJobRepository jobs;
    private final OfferRepository offers;
    private final DispatchPolicy policy;
    private final List<WorkerEligibility> eligibility;
    private final ApplicationEventPublisher events;

    DispatchService(WorkerRepository workers, DispatchJobRepository jobs, OfferRepository offers,
                    DispatchPolicy policy, List<WorkerEligibility> eligibility,
                    ApplicationEventPublisher events) {
        this.workers = workers;
        this.jobs = jobs;
        this.offers = offers;
        this.policy = policy;
        this.eligibility = eligibility;
        this.events = events;
    }

    // MARK: What a vertical asks (DispatchApi)

    @Override
    @Transactional
    public UUID request(DispatchRequest request) {
        Optional<DispatchJob> existing =
            jobs.findByJobKindAndJobRefId(request.jobKind(), request.jobRefId());
        if (existing.isPresent()) return existing.get().getId();

        OffsetDateTime now = OffsetDateTime.now();
        OffsetDateTime startAt = request.startAfter() == null || request.startAfter().isBefore(now)
            ? now : request.startAfter();
        DispatchJob job = new DispatchJob(request.jobKind(), request.jobRefId(),
            request.requestedBy(), request.workerKind(), request.categories(),
            request.pickupLatitude(), request.pickupLongitude(), request.pickupLabel(),
            request.dropoffLatitude(), request.dropoffLongitude(), request.dropoffLabel(),
            request.note(),
            startAt,
            // The clock starts when the search does, not when it was booked: an
            // order dispatched twenty minutes ahead of the kitchen must not
            // expire before anybody has been asked.
            startAt.plusSeconds(policy.requestTtlSeconds()));
        try {
            job = jobs.saveAndFlush(job);
        } catch (DataIntegrityViolationException raced) {
            // Two callers asked at once. The unique index is the arbiter; the
            // loser gets the search that already exists, which is the whole
            // point of the idempotency contract.
            return jobs.findByJobKindAndJobRefId(request.jobKind(), request.jobRefId())
                .map(DispatchJob::getId)
                .orElseThrow(() -> raced);
        }
        // The first ring goes out on the next tick rather than inline: opening a
        // wave inside the caller's transaction would make a rider's "request"
        // response wait on a candidate scan, and would publish offer events for
        // a request that might yet roll back.
        return job.getId();
    }

    /**
     * The negotiated path: {@code travel} has run a price conversation and the
     * rider picked somebody, so there is no open offer left to accept.
     *
     * <p>Everything a driver's own accept does still happens — the offer book is
     * closed, the worker goes busy in every mode, the job row settles the race —
     * because the only thing that differs is <em>who decided</em>.
     */
    @Override
    @Transactional
    public Assignment assign(JobKind jobKind, UUID jobRefId, UUID workerId) {
        DispatchJob job = jobs.findByJobKindAndJobRefId(jobKind, jobRefId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such dispatch"));
        Worker worker = workers.findById(workerId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such worker"));
        if (!job.getState().isOpen()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, taken(job));
        }
        if (worker.getStatus() == WorkerStatus.BUSY) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "They've already taken something else");
        }
        offers.findByJobIdAndWorkerId(job.getId(), workerId)
            .filter(o -> o.getState().isOpen())
            .ifPresent(o -> o.close(OfferState.ACCEPTED));
        worker.countAccepted();
        job.assignTo(worker.getId());
        withdrawOpenOffers(job.getId(), null);
        workers.findByUserIdOrderByKindAsc(worker.getUserId()).forEach(Worker::markBusy);
        try {
            jobs.saveAndFlush(job);
        } catch (OptimisticLockingFailureException somebodyElseWasQuicker) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Somebody else took that one");
        }
        events.publishEvent(new DispatchAssigned(job.getId(), job.getJobKind(), job.getJobRefId(),
            worker.getId(), worker.getUserId(), worker.getKind(), worker.getCategory(),
            job.getAssignedAt()));
        return toAssignment(worker, job);
    }

    @Override
    @Transactional
    public void cancel(JobKind jobKind, UUID jobRefId, boolean workerAtFault) {
        DispatchJob job = jobs.findByJobKindAndJobRefId(jobKind, jobRefId).orElse(null);
        // Safe for a job dispatch never heard of: a vertical cancelling an order
        // that never reached a courier shouldn't have to know whether it did.
        if (job == null || job.getState() == JobState.CANCELLED) return;
        withdrawOpenOffers(job.getId(), null);
        if (job.getAssignedWorkerId() != null) {
            workers.findById(job.getAssignedWorkerId()).ifPresent(worker -> {
                if (workerAtFault) worker.countCancelled();
                releaseAllRegistrations(worker.getUserId());
            });
            job.unassign();
        }
        job.close(JobState.CANCELLED);
    }

    @Override
    @Transactional
    public void complete(JobKind jobKind, UUID jobRefId, Integer rating) {
        DispatchJob job = jobs.findByJobKindAndJobRefId(jobKind, jobRefId).orElse(null);
        if (job == null || job.getAssignedWorkerId() == null) return;
        workers.findById(job.getAssignedWorkerId()).ifPresent(worker -> {
            worker.countCompleted(rating);
            releaseAllRegistrations(worker.getUserId());
        });
        job.close(JobState.ASSIGNED);
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<Assignment> assignmentFor(JobKind jobKind, UUID jobRefId) {
        return jobs.findByJobKindAndJobRefId(jobKind, jobRefId)
            .filter(j -> j.getAssignedWorkerId() != null)
            .flatMap(j -> workers.findById(j.getAssignedWorkerId())
                .map(w -> toAssignment(w, j)));
    }

    private static Assignment toAssignment(Worker worker, DispatchJob job) {
        return new Assignment(worker.getId(), worker.getUserId(), worker.getKind(),
            worker.getCategory(), job.getJobKind(), job.getJobRefId(),
            worker.getRating().doubleValue(), worker.getCompletedCount(),
            worker.vehicle(), job.getAssignedAt());
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<WorkerPosition> positionOf(UUID workerId) {
        return workers.findById(workerId)
            .filter(w -> w.getLatitude() != null && w.getLongitude() != null)
            .map(w -> new WorkerPosition(w.getId(), w.getUserId(),
                w.getLatitude(), w.getLongitude(), w.getPositionAt()));
    }

    @Override
    @Transactional(readOnly = true)
    public Set<WorkerKind> rolesOf(UUID userId) {
        // Suspension is not filtered out: a suspended driver is still a driver,
        // and an app that stopped saying so would have nowhere to explain why
        // no work is arriving.
        return workers.findByUserIdOrderByKindAsc(userId).stream()
            .map(Worker::getKind)
            .collect(Collectors.toCollection(() -> EnumSet.noneOf(WorkerKind.class)));
    }

    // MARK: Provisioning (called by partner, through the two public APIs)

    @Transactional
    UUID provision(WorkerKind kind, UUID userId, UUID partnerAccountId,
                   VehicleRef vehicle, String homeRegion) {
        return workers.findByUserIdAndKind(userId, kind)
            .map(Worker::getId)
            .orElseGet(() -> workers.save(new Worker(userId, kind, partnerAccountId,
                vehicle.category() == null ? VehicleCategory.defaultFor(kind) : vehicle.category(),
                homeRegion, vehicle)).getId());
    }

    /** The driver switched cars — or the one they are in earned its badge. Not a
     *  re-provisioning: it happens weekly, and it carries the one field matching
     *  reads. */
    @Transactional
    void setVehicle(WorkerKind kind, UUID workerId, VehicleRef vehicle) {
        workers.findById(workerId)
            .filter(w -> w.getKind() == kind)
            .ifPresent(w -> w.setVehicle(vehicle));
    }

    /**
     * Was this account offered this job, and which registration answered?
     *
     * <p>Answers for a closed offer too: a counteroffer <em>is</em> a decline of
     * the dispatch offer, so by the time {@code travel} runs a price conversation
     * the row is no longer open, and refusing then would make negotiation
     * impossible.
     */
    @Override
    @Transactional(readOnly = true)
    public Optional<UUID> offeredWorkerId(JobKind jobKind, UUID jobRefId, UUID userId) {
        return jobs.findByJobKindAndJobRefId(jobKind, jobRefId)
            .flatMap(job -> workers.findByUserIdAndKind(userId, job.getWorkerKind())
                .filter(worker -> offers.findByJobIdAndWorkerId(job.getId(), worker.getId())
                    .isPresent())
                .map(Worker::getId));
    }

    @Transactional
    void setSuspended(WorkerKind kind, UUID workerId, boolean suspended) {
        Worker worker = workers.findById(workerId)
            .filter(w -> w.getKind() == kind)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such " + kind.name().toLowerCase() + " registration"));
        worker.setSuspended(suspended);
        if (suspended) withdrawOffersFor(worker.getId());
    }

    // MARK: What the worker's app does

    @Transactional(readOnly = true)
    MyDispatchResponse mine(UUID userId) {
        List<Worker> mine = workers.findByUserIdOrderByKindAsc(userId);
        return new MyDispatchResponse(
            mine.stream().map(this::toWorkerDto).toList(),
            openOffersFor(mine),
            currentAssignment(mine).orElse(null),
            policy.positionIntervalSeconds());
    }

    @Transactional
    WorkerDto setAvailability(UUID userId, WorkerKind kind, boolean available) {
        Worker worker = requireRegistration(userId, kind);
        if (available && worker.isSuspended()) {
            // Named plainly rather than silently ignored: a driver toggling a
            // switch that does nothing will assume the app is broken, and the
            // real answer is one they need to act on.
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Your account is suspended — nothing will be offered to you until "
                    + "that is lifted");
        }
        worker.setAvailable(available);
        if (!available) withdrawOffersFor(worker.getId());
        return toWorkerDto(worker);
    }

    /**
     * Where they are now. Written to every registration this person holds,
     * because there is one of them and one phone: a courier who switches to
     * driving should not arrive somewhere the driver registry thinks is empty.
     */
    @Transactional
    void reportPosition(UUID userId, double latitude, double longitude) {
        List<Worker> mine = workers.findByUserIdOrderByKindAsc(userId);
        if (mine.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "You aren't registered to take work");
        }
        mine.forEach(w -> w.reportPosition(latitude, longitude));
    }

    @Transactional
    AssignmentDto accept(UUID userId, UUID offerId) {
        OffsetDateTime now = OffsetDateTime.now();
        Offer offer = offers.findById(offerId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such offer"));
        Worker worker = workers.findById(offer.getWorkerId())
            .filter(w -> w.getUserId().equals(userId))
            // 404, not 403 — somebody else's offer is not theirs to learn about.
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such offer"));
        if (!offer.getState().isOpen()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, gone(offer));
        }
        if (offer.isLapsed(now)) {
            offer.close(OfferState.EXPIRED);
            worker.countExpired();
            throw new ResponseStatusException(HttpStatus.CONFLICT, "That offer expired");
        }
        DispatchJob job = jobs.findById(offer.getJobId())
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such offer"));
        if (!job.getState().isOpen()) {
            offer.close(OfferState.WITHDRAWN);
            throw new ResponseStatusException(HttpStatus.CONFLICT, taken(job));
        }

        offer.close(OfferState.ACCEPTED);
        worker.countAccepted();
        job.assignTo(worker.getId());
        withdrawOpenOffers(job.getId(), offer.getId());
        // One person, one pair of hands: accepting anything makes every
        // registration they hold busy (SPECS §3's dual-mode rule).
        workers.findByUserIdOrderByKindAsc(userId).forEach(Worker::markBusy);
        try {
            jobs.saveAndFlush(job);
        } catch (OptimisticLockingFailureException somebodyElseWasQuicker) {
            // The database is the arbiter, not this method: two accepts a
            // millisecond apart both pass the state check above, and exactly one
            // of them survives the version column.
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Somebody else took that one");
        }
        events.publishEvent(new DispatchAssigned(job.getId(), job.getJobKind(), job.getJobRefId(),
            worker.getId(), worker.getUserId(), worker.getKind(), worker.getCategory(),
            job.getAssignedAt()));
        return toAssignmentDto(job, worker);
    }

    @Transactional
    void decline(UUID userId, UUID offerId) {
        Offer offer = offers.findById(offerId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such offer"));
        Worker worker = workers.findById(offer.getWorkerId())
            .filter(w -> w.getUserId().equals(userId))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such offer"));
        // Declining something already closed is not an error. The worker tapped
        // a card that had lapsed under their thumb, and telling them off for it
        // achieves nothing.
        if (!offer.getState().isOpen()) return;
        offer.close(OfferState.DECLINED);
        worker.countDeclined();
    }

    // MARK: The matching loop (driven by DispatchMatchingJob)

    @Transactional(readOnly = true)
    List<UUID> jobsNeedingAttention(int batch) {
        OffsetDateTime now = OffsetDateTime.now();
        PageRequest page = PageRequest.of(0, batch);
        Set<UUID> ids = new LinkedHashSet<>();
        jobs.dueForWave(JobState.SEARCHING, now, page).forEach(j -> ids.add(j.getId()));
        jobs.expired(JobState.SEARCHING, now, page).forEach(j -> ids.add(j.getId()));
        return List.copyOf(ids);
    }

    /**
     * Widens one search by a ring, or ends it.
     *
     * <p>Recomputed from the row every tick rather than held in memory, for the
     * same reason delivery's fulfilment job is: a missed run, a restart or a slow
     * deploy has to catch up, not leave somebody waiting on a wave that was
     * scheduled inside a process that has since died.
     */
    @Transactional
    void advance(UUID jobId) {
        DispatchJob job = jobs.findById(jobId).orElse(null);
        if (job == null || !job.getState().isOpen()) return;

        OffsetDateTime now = OffsetDateTime.now();
        List<Double> radii = policy.waveRadiiKm();
        boolean outOfTime = !now.isBefore(job.getExpiresAt());
        boolean ringsDone = job.getWave() >= radii.size();
        boolean anyoneStillLooking = offers.findByJobIdAndState(job.getId(), OfferState.OFFERED)
            .stream().anyMatch(o -> !o.isLapsed(now));

        if (outOfTime || (ringsDone && !anyoneStillLooking)) {
            exhaust(job);
            return;
        }
        if (ringsDone || now.isBefore(job.getNextWaveAt())) {
            // Every ring is out and somebody is still deciding. Wait for them
            // rather than declaring failure while a phone is ringing.
            job.deferWave(now.plusSeconds(policy.waveIntervalSeconds()));
            return;
        }
        openWave(job, radii.get(job.getWave()), now);
    }

    private void openWave(DispatchJob job, double radiusKm, OffsetDateTime now) {
        int wave = job.openWave(now.plusSeconds(policy.waveIntervalSeconds()));
        Set<UUID> alreadyAsked = offers.findByJobId(job.getId()).stream()
            .map(Offer::getWorkerId)
            .collect(Collectors.toSet());

        Geo.Box box = Geo.box(job.getPickupLatitude(), job.getPickupLongitude(), radiusKm);
        List<Worker> shortlist = workers.inBox(job.getWorkerKind(), WorkerStatus.AVAILABLE,
            box.minLatitude(), box.maxLatitude(), box.minLongitude(), box.maxLongitude(),
            PageRequest.of(0, SHORTLIST_LIMIT));

        List<CandidateRanker.Candidate> candidates = shortlist.stream()
            .map(w -> new CandidateRanker.Candidate(w.getId(), w.getUserId(), w.getCategory(),
                w.getLatitude(), w.getLongitude(), w.getPositionAt(),
                w.getRating().doubleValue(), w.getIdleSince()))
            .toList();
        List<CandidateRanker.Ranked> chosen = CandidateRanker.rank(candidates, policy.ranking(),
            job.getPickupLatitude(), job.getPickupLongitude(), radiusKm, job.categories(),
            alreadyAsked, userId -> mayBeOffered(job, userId), policy.waveSize(), now);

        OffsetDateTime offerExpiry = now.plusSeconds(policy.offerTtlSeconds());
        List<Worker> byId = new ArrayList<>(shortlist);
        for (CandidateRanker.Ranked ranked : chosen) {
            UUID workerId = ranked.candidate().workerId();
            Offer offer = offers.save(new Offer(job.getId(), workerId, wave, offerExpiry));
            byId.stream().filter(w -> w.getId().equals(workerId)).findFirst()
                .ifPresent(Worker::countOffered);
            events.publishEvent(new DispatchOffered(job.getId(), offer.getId(), job.getJobKind(),
                job.getJobRefId(), workerId, ranked.candidate().userId(),
                job.getPickupLabel(), offerExpiry));
        }
        if (chosen.isEmpty()) {
            log.debug("Dispatch wave {} for {} {} found nobody within {} km",
                wave, job.getJobKind(), job.getJobRefId(), radiusKm);
        }
    }

    /**
     * Asks every vertical that has an opinion whether this person may be sent
     * this job — Phase 3 M4's token check, and whatever comes after it.
     *
     * <p>A plugin that throws is treated as no objection. A matching engine that
     * stops finding drivers because a vertical had a bad second is a worse
     * failure than an offer that is later refused, and the wave is the wrong
     * place to discover that somebody else's database is down.
     */
    private boolean mayBeOffered(DispatchJob job, UUID workerUserId) {
        for (WorkerEligibility check : eligibility) {
            String refusal;
            try {
                refusal = check.refuseOffer(job.getJobKind(), job.getJobRefId(), workerUserId);
            } catch (RuntimeException broken) {
                log.warn("Eligibility check {} failed for {} — treating as eligible: {}",
                    check.getClass().getSimpleName(), workerUserId, broken.toString());
                continue;
            }
            if (refusal != null) {
                log.debug("Skipping {} for {} {}: {}", workerUserId, job.getJobKind(),
                    job.getJobRefId(), refusal);
                return false;
            }
        }
        return true;
    }

    private void exhaust(DispatchJob job) {
        withdrawOpenOffers(job.getId(), null);
        job.close(JobState.EXHAUSTED);
        int offered = offers.findByJobId(job.getId()).size();
        events.publishEvent(new DispatchExhausted(job.getId(), job.getJobKind(),
            job.getJobRefId(), offered));
    }

    /**
     * Closes offers nobody answered. A separate sweep from {@link #advance},
     * because an offer lapsing is a fact about a worker's record even when the
     * job it belonged to was assigned or cancelled long ago.
     */
    @Transactional
    int expireLapsedOffers(int batch) {
        List<Offer> lapsed = offers.findByStateAndExpiresAtBefore(OfferState.OFFERED,
            OffsetDateTime.now(), PageRequest.of(0, batch));
        for (Offer offer : lapsed) {
            offer.close(OfferState.EXPIRED);
            workers.findById(offer.getWorkerId()).ifPresent(Worker::countExpired);
        }
        return lapsed.size();
    }

    // MARK: Helpers

    private void withdrawOpenOffers(UUID jobId, UUID keepOfferId) {
        offers.findByJobIdAndState(jobId, OfferState.OFFERED).stream()
            .filter(o -> keepOfferId == null || !o.getId().equals(keepOfferId))
            // WITHDRAWN, not EXPIRED: these people lost a race nobody told them
            // they were in, and it must not count against their acceptance rate.
            .forEach(o -> o.close(OfferState.WITHDRAWN));
    }

    private void withdrawOffersFor(UUID workerId) {
        offers.findByWorkerIdAndStateOrderByOfferedAtAsc(workerId, OfferState.OFFERED)
            .forEach(o -> o.close(OfferState.WITHDRAWN));
    }

    private void releaseAllRegistrations(UUID userId) {
        workers.findByUserIdOrderByKindAsc(userId).forEach(Worker::release);
    }

    private Worker requireRegistration(UUID userId, WorkerKind kind) {
        return workers.findByUserIdAndKind(userId, kind)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "You aren't registered as a " + kind.name().toLowerCase()));
    }

    private static String gone(Offer offer) {
        return switch (offer.getState()) {
            case ACCEPTED -> "You already took that one";
            case DECLINED -> "You already turned that one down";
            case EXPIRED -> "That offer expired";
            default -> "Somebody else took that one";
        };
    }

    private static String taken(DispatchJob job) {
        return job.getState() == JobState.CANCELLED
            ? "That was cancelled"
            : "Somebody else took that one";
    }

    // MARK: Mapping

    private List<OfferDto> openOffersFor(List<Worker> mine) {
        OffsetDateTime now = OffsetDateTime.now();
        List<OfferDto> open = new ArrayList<>();
        for (Worker worker : mine) {
            for (Offer offer : offers.findByWorkerIdAndStateOrderByOfferedAtAsc(
                    worker.getId(), OfferState.OFFERED)) {
                if (offer.isLapsed(now)) continue;
                jobs.findById(offer.getJobId())
                    .filter(j -> j.getState().isOpen())
                    .ifPresent(j -> open.add(toOfferDto(offer, j, worker)));
            }
        }
        return open;
    }

    private Optional<AssignmentDto> currentAssignment(List<Worker> mine) {
        for (Worker worker : mine) {
            Optional<AssignmentDto> found = offers
                .findByWorkerIdAndStateOrderByOfferedAtAsc(worker.getId(), OfferState.ACCEPTED)
                .stream()
                .map(Offer::getJobId)
                .map(jobs::findById)
                .flatMap(Optional::stream)
                .filter(j -> j.getState() == JobState.ASSIGNED
                    && worker.getId().equals(j.getAssignedWorkerId()))
                .findFirst()
                .map(j -> toAssignmentDto(j, worker));
            if (found.isPresent()) return found;
        }
        return Optional.empty();
    }

    private OfferDto toOfferDto(Offer offer, DispatchJob job, Worker worker) {
        return new OfferDto(offer.getId(), job.getJobKind().name(), job.getJobRefId(),
            worker.getKind().name(), job.getPickupLabel(),
            job.getPickupLatitude(), job.getPickupLongitude(),
            job.getDropoffLabel(), job.getDropoffLatitude(), job.getDropoffLongitude(),
            job.getNote(),
            round(Geo.distanceKm(job.getPickupLatitude(), job.getPickupLongitude(),
                worker.getLatitude() == null ? job.getPickupLatitude() : worker.getLatitude(),
                worker.getLongitude() == null ? job.getPickupLongitude() : worker.getLongitude())),
            offer.getExpiresAt(), offer.getOfferedAt());
    }

    private AssignmentDto toAssignmentDto(DispatchJob job, Worker worker) {
        return new AssignmentDto(job.getId(), job.getJobKind().name(), job.getJobRefId(),
            worker.getId(), worker.getKind().name(), job.getPickupLabel(),
            job.getPickupLatitude(), job.getPickupLongitude(),
            job.getDropoffLabel(), job.getDropoffLatitude(), job.getDropoffLongitude(),
            job.getNote(), job.getAssignedAt());
    }

    private WorkerDto toWorkerDto(Worker worker) {
        OffsetDateTime since = OffsetDateTime.now().minusDays(30);
        long offered30 = offers.countByWorkerIdAndOfferedAtAfter(worker.getId(), since);
        long accepted30 = offers.countByWorkerIdAndStateAndOfferedAtAfter(
            worker.getId(), OfferState.ACCEPTED, since);
        long declined30 = offers.countByWorkerIdAndStateAndOfferedAtAfter(
            worker.getId(), OfferState.DECLINED, since);
        return new WorkerDto(worker.getId(), worker.getKind().name(),
            worker.getCategory().name(), worker.getStatus().name(), worker.isSuspended(),
            worker.getHomeRegion(), worker.getRating().doubleValue(), worker.getRatingCount(),
            worker.getCompletedCount(), worker.getCancelledCount(),
            worker.getLatitude(), worker.getLongitude(), worker.getPositionAt(),
            new WorkerPerformance(offered30, accepted30, declined30,
                // Rates only once there is something to divide by. "0%
                // acceptance" on a driver's first day is a number that reads as
                // an accusation.
                offered30 == 0 ? null : rate(accepted30, offered30),
                offered30 == 0 ? null : rate(declined30, offered30)));
    }

    private static Double rate(long part, long whole) {
        return whole <= 0 ? null : Math.round(part * 1000.0 / whole) / 10.0;
    }

    private static double round(double km) {
        return Math.round(km * 100) / 100.0;
    }
}
