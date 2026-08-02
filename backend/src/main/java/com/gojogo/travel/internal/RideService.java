package com.gojogo.travel.internal;

import com.gojogo.dispatch.Assignment;
import com.gojogo.dispatch.DispatchApi;
import com.gojogo.dispatch.DispatchRequest;
import com.gojogo.dispatch.JobKind;
import com.gojogo.dispatch.VehicleCategory;
import com.gojogo.dispatch.WorkerKind;
import com.gojogo.dispatch.WorkerPosition;
import com.gojogo.messaging.ConversationContext;
import com.gojogo.messaging.MessagingApi;
import com.gojogo.payments.AccountRef;
import com.gojogo.payments.Bucket;
import com.gojogo.payments.InsufficientFundsException;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.WalletApi;
import com.gojogo.profile.EmergencyContactDto;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import com.gojogo.share.ShareApi;
import com.gojogo.travel.RideStatusChanged;
import com.gojogo.travel.SosRaised;
import com.gojogo.travel.TripCompleted;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.EnumSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

/**
 * The ride, end to end.
 *
 * <p>Most of this is a state machine, and the interesting third of it is the
 * negotiation — the one thing a delivery order does not have. The shape worth
 * holding in mind:
 *
 * <ol>
 *   <li>The rider requests at a price. {@code dispatch} starts asking drivers.</li>
 *   <li>A driver who is happy with that price <b>accepts in dispatch</b>, and the
 *       {@code DispatchAssigned} event confirms the ride. Nothing here runs.</li>
 *   <li>A driver who is not <b>declines in dispatch</b> and posts a counter here.
 *       The rider accepts it, counters back once, or ignores it.</li>
 *   <li>Whoever accepts last causes {@link DispatchApi#assign} — and the job row
 *       is still the arbiter, so a counter accepted a second after somebody took
 *       the trip at the asking price loses, exactly as a second driver would.</li>
 * </ol>
 *
 * <p><b>The fare freezes at CONFIRMED.</b> Everything after that reads
 * {@code agreedFareMinor} and nothing recomputes it.
 */
@Service
class RideService {

    private static final Logger log = LoggerFactory.getLogger(RideService.class);

    private static final Set<RideState> OPEN =
        EnumSet.of(RideState.REQUESTED, RideState.NEGOTIATING);
    private static final Set<RideState> LIVE =
        EnumSet.of(RideState.REQUESTED, RideState.NEGOTIATING, RideState.CONFIRMED,
            RideState.ARRIVING, RideState.IN_TRIP);

    private final RideRepository rides;
    private final RideOfferRepository offers;
    private final PricingConfigRepository pricing;
    private final TravelPolicy policy;
    private final DispatchApi dispatch;
    private final WalletApi wallet;
    private final RideTokenService rideTokens;
    private final MessagingApi messaging;
    private final ProfileApi profiles;
    private final ShareApi share;
    private final ApplicationEventPublisher events;

    RideService(RideRepository rides, RideOfferRepository offers, PricingConfigRepository pricing,
                TravelPolicy policy, DispatchApi dispatch, WalletApi wallet,
                RideTokenService rideTokens, MessagingApi messaging, ProfileApi profiles,
                ShareApi share, ApplicationEventPublisher events) {
        this.rides = rides;
        this.offers = offers;
        this.pricing = pricing;
        this.policy = policy;
        this.dispatch = dispatch;
        this.wallet = wallet;
        this.rideTokens = rideTokens;
        this.messaging = messaging;
        this.profiles = profiles;
        this.share = share;
        this.events = events;
    }

    // MARK: Quoting

    /**
     * What a trip would cost, before anybody commits to anything.
     *
     * <p>Returned for <em>every</em> category rather than the one asked for, so
     * the picker shows real prices instead of making the rider tap through six
     * screens to compare them.
     */
    @Transactional(readOnly = true)
    QuoteResponse quote(QuoteRequest request) {
        Fares.Route route = Fares.estimate(request.pickupLatitude(), request.pickupLongitude(),
            request.dropoffLatitude(), request.dropoffLongitude(),
            policy.roadFactorBps(), policy.speedKmh());
        List<QuotedCategory> quoted = EnumSet.allOf(VehicleCategory.class).stream()
            .map(category -> pricingFor(category)
                .map(p -> new QuotedCategory(category.name(), Fares.suggest(route, p),
                    p.minimumMinor()))
                .orElse(null))
            .filter(java.util.Objects::nonNull)
            .toList();
        return new QuoteResponse(route.metres(), route.seconds(), wallet.currency(), quoted);
    }

    // MARK: Requesting

    /**
     * Books a ride and sets dispatch looking.
     *
     * <p>One live ride per rider, refused by name. A person cannot be in two
     * cars, and letting them request a second is how two drivers turn up at one
     * address — with two people out of pocket and nobody to blame.
     */
    @Transactional
    RideDto request(UUID riderId, RequestRideRequest request) {
        if (!liveRideFor(riderId).isEmpty()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "You already have a ride in progress");
        }
        VehicleCategory category = parseCategory(request.category());
        Fares.Pricing price = pricingFor(category).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "We don't have prices for that vehicle yet"));
        Fares.Route route = Fares.estimate(request.pickupLatitude(), request.pickupLongitude(),
            request.dropoffLatitude(), request.dropoffLongitude(),
            policy.roadFactorBps(), policy.speedKmh());
        long suggested = Fares.suggest(route, price);
        long offered = request.offeredFareMinor() == null || request.offeredFareMinor() <= 0
            ? suggested : request.offeredFareMinor();
        if (!Fares.isAcceptableOffer(offered, suggested, price, policy.maxOfferMultipleBps())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "That fare isn't in range — the minimum for this vehicle is "
                    + money(price.minimumMinor()));
        }
        // Checked here as well as at confirmation, because being told at the
        // moment you ask is kinder than being told after four drivers have
        // looked at your trip.
        requireFunds(riderId, offered);

        Ride ride = rides.saveAndFlush(new Ride(riderId, category.name(),
            request.pickupLatitude(), request.pickupLongitude(), request.pickupLabel(),
            request.dropoffLatitude(), request.dropoffLongitude(), request.dropoffLabel(),
            request.note(), route.metres(), route.seconds(), suggested, offered,
            wallet.currency(), OffsetDateTime.now().plusSeconds(policy.requestTtlSeconds())));

        dispatch.request(new DispatchRequest(JobKind.RIDE, ride.getId(), WorkerKind.DRIVER,
            EnumSet.of(category), riderId,
            ride.getPickupLatitude(), ride.getPickupLongitude(), ride.getPickupLabel(),
            ride.getDropoffLatitude(), ride.getDropoffLongitude(), ride.getDropoffLabel(),
            ride.getNote(), null));
        return toDto(ride, riderId);
    }

    // MARK: Negotiation

    /**
     * A driver's counteroffer.
     *
     * <p>Only from somebody dispatch actually put this trip in front of —
     * otherwise any driver in the city could bid on any ride — and only once per
     * driver per round, so a counter is a price rather than a stream of them.
     */
    @Transactional
    RideOfferDto counter(UUID driverUserId, UUID rideId, long amountMinor) {
        Ride ride = require(rideId);
        if (!ride.getState().isOpen()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, closedMessage(ride));
        }
        UUID workerId = dispatch.offeredWorkerId(JobKind.RIDE, rideId, driverUserId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "That trip wasn't offered to you"));
        Fares.Pricing price = pricingFor(parseCategory(ride.getCategory())).orElseThrow();
        if (!Fares.isAcceptableOffer(amountMinor, ride.getSuggestedFareMinor(), price,
                policy.maxOfferMultipleBps())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "That fare isn't in range");
        }
        List<RideOffer> mine = offers.findByRideIdAndDriverWorkerIdOrderByCreatedAtAsc(
            rideId, workerId);
        int round = mine.size() + 1;
        if (round > policy.maxRounds()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "You've both had your say on this one");
        }
        // A driver's second price replaces their first — leaving two live
        // offers from the same person would let them be accepted at whichever
        // one the rider tapped, which is not a negotiation, it is a trap.
        mine.stream().filter(o -> o.getState().isOpen())
            .forEach(o -> o.close(RideOfferState.WITHDRAWN));

        RideOffer offer = offers.save(new RideOffer(rideId, workerId, driverUserId,
            OfferParty.DRIVER, amountMinor, round,
            OffsetDateTime.now().plusSeconds(policy.offerTtlSeconds())));
        ride.enterNegotiation();
        return toOfferDto(offer);
    }

    /**
     * The rider's answer to a counter: take it, or come back with one more.
     *
     * <p>A rider's counter is addressed to <em>that driver</em> and nobody else,
     * which is why it carries their worker id: three drivers countering is three
     * separate conversations, and a reply broadcast to all of them would be an
     * auction.
     */
    @Transactional
    RideOfferDto counterBack(UUID riderId, UUID rideId, UUID offerId, long amountMinor) {
        Ride ride = requireRider(riderId, rideId);
        if (!ride.getState().isOpen()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, closedMessage(ride));
        }
        RideOffer theirs = requireOffer(rideId, offerId);
        if (!theirs.answerableBy(OfferParty.RIDER)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, offerGoneMessage(theirs));
        }
        Fares.Pricing price = pricingFor(parseCategory(ride.getCategory())).orElseThrow();
        if (!Fares.isAcceptableOffer(amountMinor, ride.getSuggestedFareMinor(), price,
                policy.maxOfferMultipleBps())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "That fare isn't in range");
        }
        if (theirs.getRound() + 1 > policy.maxRounds()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "You've both had your say — take it or leave it");
        }
        requireFunds(riderId, amountMinor);
        theirs.close(RideOfferState.DECLINED);
        RideOffer mine = offers.save(new RideOffer(rideId, theirs.getDriverWorkerId(),
            theirs.getDriverUserId(), OfferParty.RIDER, amountMinor, theirs.getRound() + 1,
            OffsetDateTime.now().plusSeconds(policy.offerTtlSeconds())));
        return toOfferDto(mine);
    }

    /** The rider takes a driver's price. */
    @Transactional
    RideDto acceptAsRider(UUID riderId, UUID rideId, UUID offerId) {
        Ride ride = requireRider(riderId, rideId);
        RideOffer offer = requireOffer(rideId, offerId);
        if (!offer.answerableBy(OfferParty.RIDER)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, offerGoneMessage(offer));
        }
        return settleOn(ride, offer);
    }

    /** The driver takes the rider's counter. */
    @Transactional
    RideDto acceptAsDriver(UUID driverUserId, UUID rideId, UUID offerId) {
        Ride ride = require(rideId);
        RideOffer offer = requireOffer(rideId, offerId);
        if (!offer.getDriverUserId().equals(driverUserId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such offer");
        }
        if (!offer.answerableBy(OfferParty.DRIVER)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, offerGoneMessage(offer));
        }
        return settleOn(ride, offer);
    }

    @Transactional
    void declineOffer(UUID riderId, UUID rideId, UUID offerId) {
        requireRider(riderId, rideId);
        RideOffer offer = requireOffer(rideId, offerId);
        // Declining something already closed is not an error — they tapped a
        // card that lapsed under their thumb.
        if (offer.answerableBy(OfferParty.RIDER)) offer.close(RideOfferState.DECLINED);
    }

    /**
     * Somebody accepted a price. This is where the negotiation becomes a trip.
     *
     * <p>The order matters: dispatch assigns <em>first</em>, because that is the
     * call that can refuse. If somebody else took the job a second ago it throws
     * a 409 and nothing here has been written.
     */
    private RideDto settleOn(Ride ride, RideOffer offer) {
        if (!ride.getState().isOpen()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, closedMessage(ride));
        }
        if (offer.isLapsed(OffsetDateTime.now())) {
            offer.close(RideOfferState.EXPIRED);
            throw new ResponseStatusException(HttpStatus.CONFLICT, "That price expired");
        }
        requireFunds(ride.getRiderId(), offer.getAmountMinor());
        Assignment assignment = dispatch.assign(JobKind.RIDE, ride.getId(),
            offer.getDriverWorkerId());
        offer.close(RideOfferState.ACCEPTED);
        withdrawOtherOffers(ride.getId(), offer.getId());
        confirm(ride, assignment, offer.getAmountMinor());
        return toDto(ride, ride.getRiderId());
    }

    /**
     * Matched — from either route: a driver accepting in dispatch at the asking
     * price, or a negotiated price settled above.
     *
     * <p>The tokens are charged <em>after</em> the row survives its optimistic
     * lock (Phase 3 M4). Charging first would mean the loser of a race pays for
     * a trip they did not get, and the refund for that is a correction nobody
     * asked for rather than a movement that never happened.
     */
    private void confirm(Ride ride, Assignment assignment, long fareMinor) {
        ride.confirm(assignment.workerId(), assignment.userId(),
            assignment.vehicle(), fareMinor);
        try {
            rides.saveAndFlush(ride);
        } catch (OptimisticLockingFailureException raced) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Somebody else took that one");
        }
        ride.recordTokenCost(rideTokens.charge(ride));
        openConversation(ride);
        publishStatus(ride, ride.getRiderId());
    }

    /**
     * A driver accepted in dispatch, at the price the rider asked. Called from
     * the event listener, which is why it takes an assignment rather than a
     * request.
     *
     * <p><b>{@code REQUIRES_NEW}, and it is load-bearing.</b> This runs from an
     * {@code AFTER_COMMIT} listener, where the just-committed transaction's
     * resources are still bound to the thread — so plain {@code REQUIRED} joins
     * a transaction that is finished, and the first flush fails with "no
     * transaction is in progress". The dispatch job is assigned by then, so the
     * damage is a worker marked busy for a ride that never confirmed and a rider
     * told nothing. Found in production on 2026-08-01, the first time anybody
     * accepted a real ride offer at the asking price.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void confirmFromDispatch(UUID rideId, Assignment assignment) {
        Ride ride = rides.findById(rideId).orElse(null);
        if (ride == null || !ride.getState().isOpen()) return;
        withdrawOtherOffers(rideId, null);
        confirm(ride, assignment, ride.getOfferedFareMinor());
    }

    /** Nobody took it. {@code REQUIRES_NEW} for the same reason as
     *  {@link #confirmFromDispatch} — the other listener entry point, and it
     *  writes too. */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void exhaust(UUID rideId) {
        Ride ride = rides.findById(rideId).orElse(null);
        if (ride == null || !ride.getState().isOpen()) return;
        // A live counteroffer means somebody is still interested even though
        // dispatch has stopped asking — ending the ride under them would throw
        // away the only driver who wanted it.
        boolean stillTalking = offers.findByRideIdAndState(rideId, RideOfferState.PENDING)
            .stream().anyMatch(o -> !o.isLapsed(OffsetDateTime.now()));
        if (stillTalking) return;
        expire(ride);
    }

    // MARK: The trip

    @Transactional
    RideDto driverArriving(UUID driverUserId, UUID rideId) {
        Ride ride = requireDriver(driverUserId, rideId);
        requireState(ride, RideState.CONFIRMED);
        ride.markArriving();
        publishStatus(ride, ride.getRiderId());
        return toDto(ride, driverUserId);
    }

    @Transactional
    RideDto startTrip(UUID driverUserId, UUID rideId) {
        Ride ride = requireDriver(driverUserId, rideId);
        if (ride.getState() != RideState.CONFIRMED && ride.getState() != RideState.ARRIVING) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That trip isn't ready to start");
        }
        ride.start();
        publishStatus(ride, ride.getRiderId());
        return toDto(ride, driverUserId);
    }

    /**
     * The trip is over, and this is where money moves — once, at completion, with
     * no escrow (SPECS §1) and no commission: rides carry none, because the
     * platform's revenue is Phase 3 M4's tokens.
     *
     * <p>So it is a single transfer from the rider's wallet to the driver's, not
     * a split. The idempotency key is the ride, so a driver who taps twice pays
     * themselves once.
     */
    @Transactional
    RideDto complete(UUID driverUserId, UUID rideId) {
        Ride ride = requireDriver(driverUserId, rideId);
        requireState(ride, RideState.IN_TRIP);
        long fare = ride.getAgreedFareMinor() == null ? 0 : ride.getAgreedFareMinor();
        if (fare > 0) {
            try {
                wallet.transfer(
                    AccountRef.user(ride.getRiderId(), Bucket.AVAILABLE),
                    AccountRef.user(ride.getDriverUserId(), Bucket.AVAILABLE),
                    fare, LedgerKind.RIDE_FARE,
                    WalletApi.Reference.of("RIDE", ride.getId(),
                        "Trip to " + shortLabel(ride.getDropoffLabel())),
                    "ride:" + ride.getId() + ":fare");
            } catch (InsufficientFundsException emptyWallet) {
                // Checked at request and again at confirmation, so reaching here
                // means the rider spent the money mid-trip. The trip still
                // happened: complete it, record the debt as unpaid rather than
                // trapping the driver in a state they cannot leave.
                log.warn("Ride {} completed but the rider could not pay {}: {}",
                    ride.getId(), fare, emptyWallet.getMessage());
                throw new ResponseStatusException(HttpStatus.PAYMENT_REQUIRED,
                    "Your passenger's wallet couldn't cover the fare — "
                        + "tap again once they've topped up");
            }
        }
        ride.complete();
        dispatch.complete(JobKind.RIDE, ride.getId(), null);
        // Share links are deliberately *not* revoked here. A link that dies at
        // the kerb dies at the one moment the person watching cares about it, so
        // the trip's own grace window (safety.share.grace.minutes) lets them see
        // "Arrived safely" instead of a dead page.
        // vehicleId is what makes Phase 3 M5's community verification land on
        // the car this passenger actually rode in, rather than on whatever the
        // driver has made active by the time they answer.
        events.publishEvent(new TripCompleted(ride.getId(), ride.getRiderId(),
            ride.getDriverUserId(), ride.getDriverWorkerId(), ride.getVehicleId(), fare,
            ride.getCurrency(), OffsetDateTime.now()));
        publishStatus(ride, ride.getRiderId());
        return toDto(ride, driverUserId);
    }

    /**
     * Either side calls it off.
     *
     * <p>A rider is free until a driver has actually started moving — changing
     * your mind is free, and the fee exists to compensate somebody who drove, not
     * to punish somebody who hesitated. A driver cancelling is always free to the
     * rider and always counts against the driver.
     */
    @Transactional
    RideDto cancel(UUID callerId, UUID rideId, String reason) {
        Ride ride = require(rideId);
        boolean byRider = ride.getRiderId().equals(callerId);
        boolean byDriver = callerId.equals(ride.getDriverUserId());
        if (!byRider && !byDriver) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such ride");
        }
        if (ride.getState().isFinished()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "That ride is already over");
        }
        if (ride.getState() == RideState.IN_TRIP) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "A trip in progress can't be cancelled — end it instead");
        }
        long fee = 0;
        if (byRider && ride.getState() == RideState.ARRIVING) {
            fee = chargeCancelFee(ride);
        }
        // The tokens follow the trip, not the fault. SPECS §4 returns them only
        // on a driver-fault cancellation; that would make cancelling a source of
        // revenue for the platform and would charge a driver for a rider's
        // change of mind — the first is an incentive nobody should install in a
        // dispatch system, and the second teaches drivers to decline. A driver
        // who accepts and cancels repeatedly is already priced: dispatch counts
        // every one of those against them.
        rideTokens.refund(ride);
        withdrawOtherOffers(rideId, null);
        ride.cancel(byRider, reason, fee);
        dispatch.cancel(JobKind.RIDE, rideId, byDriver);
        // Told to the *other* party: your own cancellation is not news to you.
        publishStatus(ride, byRider ? ride.getDriverUserId() : ride.getRiderId());
        return toDto(ride, callerId);
    }

    /** The driver's time, not the platform's — so it is paid to them. */
    private long chargeCancelFee(Ride ride) {
        long fee = policy.cancelFeeMinor();
        if (fee <= 0 || ride.getDriverUserId() == null) return 0;
        try {
            wallet.transfer(
                AccountRef.user(ride.getRiderId(), Bucket.AVAILABLE),
                AccountRef.user(ride.getDriverUserId(), Bucket.AVAILABLE),
                fee, LedgerKind.RIDE_FARE,
                WalletApi.Reference.of("RIDE", ride.getId(), "Cancellation fee"),
                "ride:" + ride.getId() + ":cancelfee");
            return fee;
        } catch (InsufficientFundsException nothingToTake) {
            // Not a reason to refuse the cancellation. The trip is not happening
            // either way, and trapping a rider in a ride they cannot pay to leave
            // is worse than a driver missing two dollars.
            log.info("Cancellation fee waived on ride {}: rider's wallet is empty", ride.getId());
            return 0;
        }
    }

    private void expire(Ride ride) {
        withdrawOtherOffers(ride.getId(), null);
        ride.expire();
        dispatch.cancel(JobKind.RIDE, ride.getId(), false);
        publishStatus(ride, ride.getRiderId());
    }

    // MARK: Safety (Phase 3 M5, SPECS §10)

    /**
     * A public link to this trip, for somebody who is not in the app.
     *
     * <p>Either party may make one — a driver working late has as much reason to
     * be watched as a rider does — and only while the trip is live: sharing a
     * finished trip is sharing a receipt, and sharing one that has not been
     * matched yet is sharing an empty map.
     */
    @Transactional
    ShareTripDto shareTrip(UUID callerId, UUID rideId) {
        Ride ride = requireParty(callerId, rideId);
        if (!ride.getState().isLive()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                ride.getState().isFinished()
                    ? "That trip is over — there's nothing left to follow"
                    : "You can share a trip once a driver has taken it");
        }
        ShareApi.SharedLink link = share.mint(RideShareableResource.KIND, ride.getId(), callerId,
            ShareApi.ShareReason.SHARE, shareTtl(ride));
        return new ShareTripDto(link.url(), link.expiresAt(), link.viewCount(),
            "I'm on a GoJoGo trip to " + shortLabel(ride.getDropoffLabel())
                + ". You can follow it here: " + link.url());
    }

    /** Stop sharing. The link is dead from the next request — which is all
     *  "stop sharing" can ever mean once a URL has been sent to somebody. */
    @Transactional
    void stopSharing(UUID callerId, UUID rideId) {
        requireParty(callerId, rideId);
        share.revoke(RideShareableResource.KIND, rideId, callerId);
    }

    /**
     * The button.
     *
     * <p>Three things happen, in an order chosen so the most important one
     * cannot be lost: the ride is <strong>flagged first</strong> (that is what
     * puts it in front of an operator and it must survive everything else
     * failing), then a link is minted, then the alert goes out as an event.
     *
     * <p><strong>What this deliberately does not do is call anybody.</strong>
     * The emergency number is returned to the app and dialled from the phone,
     * because a server placing an emergency call on somebody's behalf is a claim
     * about integration with emergency services that this system has no right to
     * make (SPECS §10: "no PSAP integration claimed"). What the server can
     * honestly do is make sure the people who love this person know where they
     * are.
     *
     * <p>Contacts who are also GojoGo accounts get a push. Contacts who are only
     * a phone number come back in the response with the message already written,
     * for the phone's own composer — the only channel that actually works while
     * SMS is still sandboxed, and the one whose message arrives from a number the
     * recipient recognises.
     */
    @Transactional
    SosDto raiseSos(UUID callerId, UUID rideId) {
        Ride ride = requireParty(callerId, rideId);
        if (ride.getState().isFinished()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That trip is over. If you're in danger, call the emergency number.");
        }
        ride.raiseSos(callerId);
        rides.flush();
        log.error("SOS raised on ride {} by {}", rideId, callerId);

        ShareApi.SharedLink link = share.mint(RideShareableResource.KIND, ride.getId(), callerId,
            ShareApi.ShareReason.SOS, shareTtl(ride));
        List<EmergencyContactDto> contacts = profiles.emergencyContactsOf(callerId);
        List<UUID> reachable = contacts.stream()
            .map(EmergencyContactDto::linkedProfileId)
            .filter(java.util.Objects::nonNull)
            .toList();
        String message = sosMessage(ride, link.url());
        events.publishEvent(new SosRaised(ride.getId(), callerId, callerName(callerId),
            ride.getRiderId(), ride.getDriverUserId(), reachable, link.url(),
            ride.getPickupLabel(), ride.getDropoffLabel(), ride.getVehicleLabel(),
            ride.getVehiclePlate(), ride.getPickupLatitude(), ride.getPickupLongitude(),
            OffsetDateTime.now()));
        return new SosDto(emergencyNumber(), link.url(), message, contacts, reachable.size(),
            OffsetDateTime.now());
    }

    /**
     * A link lives as long as the trip plus a grace, and never less than the
     * configured floor.
     *
     * <p>Derived from the trip's own duration estimate rather than a flat number
     * because the two failure modes are asymmetric: a link that outlives a short
     * trip is harmless, and one that dies during a long one is the feature not
     * working.
     */
    private java.time.Duration shareTtl(Ride ride) {
        long floorMinutes = Math.max(5, policy.shareTtlMinutes());
        long tripMinutes = Math.max(0, ride.getDurationSeconds() / 60L);
        return java.time.Duration.ofMinutes(
            Math.max(floorMinutes, tripMinutes + policy.shareGraceMinutes()));
    }

    /** The local emergency number, by the ride's region where one is configured.
     *  112 is the default because it works across the EU and on most GSM
     *  networks worldwide, which is the right answer when we do not know. */
    private String emergencyNumber() {
        return policy.emergencyNumber();
    }

    private String sosMessage(Ride ride, String url) {
        return "I've raised an SOS on a GoJoGo trip"
            + (ride.getVehiclePlate() == null || ride.getVehiclePlate().isBlank()
                ? "" : " (" + ride.getVehicleLabel() + ", " + ride.getVehiclePlate() + ")")
            + ". Follow me here: " + url;
    }

    private String callerName(UUID userId) {
        return profiles.findById(userId).map(RideService::displayName).orElse("A GoJoGo user");
    }

    /** The operator's list (Phase 3 M5). Flagged trips, newest first — reports
     *  pile up with nobody looking at them unless there is somewhere to look. */
    @Transactional(readOnly = true)
    List<SosRideDto> sosRides(int limit) {
        return rides.withSos(PageRequest.of(0, Math.clamp(limit, 1, 200))).stream()
            .map(ride -> new SosRideDto(ride.getId(), ride.getState().name(), ride.getSosAt(),
                ride.getSosBy(), ride.getRiderId(), ride.getDriverUserId(),
                otherPartyName(ride, ride.getDriverUserId() == null
                    ? ride.getRiderId() : ride.getDriverUserId()),
                ride.getPickupLabel(), ride.getDropoffLabel(),
                ride.getVehicleLabel(), ride.getVehiclePlate(), ride.getRequestedAt()))
            .toList();
    }

    // MARK: Rating

    /**
     * Mutual, and blind until both are in — a driver who can read a one-star
     * before writing their own is being invited to answer it, which is how a
     * rating stops measuring the trip and starts measuring the last person to tap.
     */
    @Transactional
    RideDto rate(UUID callerId, UUID rideId, int stars) {
        Ride ride = require(rideId);
        if (ride.getState() != RideState.COMPLETED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "You can only rate a finished trip");
        }
        if (ride.getCompletedAt() != null && ride.getCompletedAt()
                .plusDays(policy.ratingWindowDays()).isBefore(OffsetDateTime.now())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That trip is too old to rate now");
        }
        if (ride.getRiderId().equals(callerId)) {
            if (ride.getDriverRating() != null) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "You already rated this");
            }
            ride.rateDriver(stars);
            // The driver's dispatch rating is the average of these, kept there
            // because that is what matching filters on.
            dispatch.complete(JobKind.RIDE, ride.getId(), stars);
        } else if (callerId.equals(ride.getDriverUserId())) {
            if (ride.getRiderRating() != null) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "You already rated this");
            }
            ride.rateRider(stars);
        } else {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such ride");
        }
        return toDto(ride, callerId);
    }

    // MARK: Reads

    @Transactional(readOnly = true)
    Optional<RideDto> liveFor(UUID userId) {
        return liveRideFor(userId).stream().findFirst()
            .or(() -> rides.liveForDriver(userId, LIVE, PageRequest.of(0, 1)).stream().findFirst())
            .map(ride -> toDto(ride, userId));
    }

    @Transactional(readOnly = true)
    RideDto get(UUID callerId, UUID rideId) {
        Ride ride = require(rideId);
        if (!ride.getRiderId().equals(callerId) && !callerId.equals(ride.getDriverUserId())) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such ride");
        }
        return toDto(ride, callerId);
    }

    @Transactional(readOnly = true)
    List<RideDto> history(UUID userId, int limit) {
        PageRequest page = PageRequest.of(0, Math.clamp(limit, 1, 100));
        List<Ride> mine = rides.findByRiderIdOrderByRequestedAtDesc(userId, page);
        if (mine.isEmpty()) mine = rides.findByDriverUserIdOrderByRequestedAtDesc(userId, page);
        return mine.stream().map(ride -> toDto(ride, userId)).toList();
    }

    /** The driver's side: rides they were offered and countered on, plus the one
     *  they are running. */
    @Transactional(readOnly = true)
    List<RideOfferDto> myOffers(UUID driverUserId) {
        OffsetDateTime now = OffsetDateTime.now();
        return offers.findByDriverUserIdAndStateOrderByCreatedAtAsc(
                driverUserId, RideOfferState.PENDING).stream()
            .filter(o -> !o.isLapsed(now))
            .map(this::toOfferDto)
            .toList();
    }

    /**
     * The driver's token standing and the price list behind it (Phase 3 M4).
     *
     * <p>Lives on {@code travel} rather than {@code payments} because only this
     * module knows what a ride costs — and only this module can therefore say
     * whether a balance is enough to work with, which is the sentence a driver
     * with an empty screen actually needs.
     */
    @Transactional(readOnly = true)
    MyRideTokensDto myTokens(UUID driverUserId) {
        String refusal = rideTokens.refusalFor(driverUserId);
        return new MyRideTokensDto(rideTokens.balanceOf(driverUserId),
            rideTokens.cheapestRide(), refusal == null, refusal, rideTokens.priceList());
    }

    // MARK: The sweep

    @Transactional(readOnly = true)
    List<UUID> expiredRideIds(int batch) {
        return rides.expired(OPEN, OffsetDateTime.now(), PageRequest.of(0, batch)).stream()
            .map(Ride::getId)
            .toList();
    }

    @Transactional
    void expireIfStillOpen(UUID rideId) {
        Ride ride = rides.findById(rideId).orElse(null);
        if (ride == null || !ride.getState().isOpen()) return;
        if (ride.getExpiresAt().isAfter(OffsetDateTime.now())) return;
        expire(ride);
    }

    @Transactional
    int expireLapsedOffers(int batch) {
        List<RideOffer> lapsed = offers.findByStateAndExpiresAtBefore(RideOfferState.PENDING,
            OffsetDateTime.now(), PageRequest.of(0, batch));
        lapsed.forEach(o -> o.close(RideOfferState.EXPIRED));
        return lapsed.size();
    }

    // MARK: Helpers

    private List<Ride> liveRideFor(UUID riderId) {
        return rides.liveForRider(riderId, LIVE, PageRequest.of(0, 1));
    }

    /**
     * Refuses a fare the rider cannot cover.
     *
     * <p>SPECS §1 gives rides no escrow — the money moves at completion — which
     * leaves a hole this fills: a fare nobody can pay should be refused while the
     * trip can still not happen, rather than after somebody has been driven across
     * a city. It is a check, not a hold: the money stays spendable, and the
     * failure mode it does not cover (spending it mid-trip) is handled at
     * completion.
     */
    private void requireFunds(UUID riderId, long amountMinor) {
        long available = wallet.balancesOf(OwnerKind.USER, riderId).available();
        if (available >= amountMinor) return;
        throw new InsufficientFundsException(amountMinor, available, wallet.currency());
    }

    private void withdrawOtherOffers(UUID rideId, UUID keepOfferId) {
        offers.findByRideIdAndState(rideId, RideOfferState.PENDING).stream()
            .filter(o -> keepOfferId == null || !o.getId().equals(keepOfferId))
            .forEach(o -> o.close(RideOfferState.WITHDRAWN));
    }

    /**
     * Opens the rider↔driver thread with a card back to the trip — the
     * {@code ConversationContext(kind=RIDE)} the messaging module has been shaped
     * for since 2b M3.
     *
     * <p>Failures are logged and swallowed on purpose: a chat thread that did not
     * open is an inconvenience, and rolling back a confirmed ride over one would
     * be an outage.
     */
    private void openConversation(Ride ride) {
        try {
            UUID conversation = messaging.openDirectConversation(
                ride.getRiderId(), ride.getDriverUserId(),
                new ConversationContext("ride", ride.getId().toString(),
                    "Trip to " + shortLabel(ride.getDropoffLabel()),
                    money(ride.getAgreedFareMinor() == null ? 0 : ride.getAgreedFareMinor()),
                    null));
            ride.attachConversation(conversation);
        } catch (RuntimeException e) {
            log.warn("Couldn't open the chat for ride {}: {}", ride.getId(), e.toString());
        }
    }

    private void publishStatus(Ride ride, UUID recipientId) {
        if (recipientId == null) return;
        events.publishEvent(new RideStatusChanged(ride.getId(), recipientId,
            ride.getState().name(), otherPartyName(ride, recipientId),
            ride.getAgreedFareMinor() == null ? 0 : ride.getAgreedFareMinor(),
            ride.getCurrency()));
    }

    private String otherPartyName(Ride ride, UUID recipientId) {
        UUID other = recipientId.equals(ride.getRiderId())
            ? ride.getDriverUserId() : ride.getRiderId();
        if (other == null) return "";
        return profiles.findById(other).map(RideService::displayName).orElse("");
    }

    private static String displayName(ProfileDto profile) {
        return profile.displayName() == null || profile.displayName().isBlank()
            ? "@" + profile.handle() : profile.displayName();
    }

    private Optional<Fares.Pricing> pricingFor(VehicleCategory category) {
        return pricing.inForce(category.name(), OffsetDateTime.now(), PageRequest.of(0, 1))
            .stream().findFirst()
            .map(PricingConfig::toPricing);
    }

    private Ride require(UUID rideId) {
        return rides.findById(rideId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "No such ride"));
    }

    /** 404 rather than 403 for somebody else's ride — don't confirm it exists. */
    private Ride requireRider(UUID riderId, UUID rideId) {
        return rides.findById(rideId)
            .filter(r -> r.getRiderId().equals(riderId))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such ride"));
    }

    /** Either side of the trip, and nobody else. 404 for a stranger's ride. */
    private Ride requireParty(UUID callerId, UUID rideId) {
        return rides.findById(rideId)
            .filter(r -> r.getRiderId().equals(callerId) || callerId.equals(r.getDriverUserId()))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such ride"));
    }

    private Ride requireDriver(UUID driverUserId, UUID rideId) {
        return rides.findById(rideId)
            .filter(r -> driverUserId.equals(r.getDriverUserId()))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such ride"));
    }

    private RideOffer requireOffer(UUID rideId, UUID offerId) {
        return offers.findById(offerId)
            .filter(o -> o.getRideId().equals(rideId))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such offer"));
    }

    private static void requireState(Ride ride, RideState expected) {
        if (ride.getState() != expected) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That trip is " + ride.getState().name().toLowerCase().replace('_', ' '));
        }
    }

    private static String closedMessage(Ride ride) {
        return switch (ride.getState()) {
            case EXPIRED -> "That request timed out";
            case CANCELLED_RIDER, CANCELLED_DRIVER -> "That ride was cancelled";
            default -> "Somebody else took that one";
        };
    }

    private static String offerGoneMessage(RideOffer offer) {
        return switch (offer.getState()) {
            case ACCEPTED -> "That price was already taken";
            case DECLINED -> "That price was turned down";
            case EXPIRED -> "That price expired";
            case WITHDRAWN -> "That price is no longer on the table";
            default -> "You can't answer your own price";
        };
    }

    private static VehicleCategory parseCategory(String name) {
        try {
            return VehicleCategory.valueOf(name.trim().toUpperCase());
        } catch (RuntimeException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Unknown vehicle category; use one of "
                    + EnumSet.allOf(VehicleCategory.class));
        }
    }

    private static String shortLabel(String label) {
        if (label == null || label.isBlank()) return "your destination";
        int comma = label.indexOf(',');
        return comma > 0 ? label.substring(0, comma) : label;
    }

    private String money(long minor) {
        return wallet.currency() + " " + String.format("%.2f", minor / 100d);
    }

    // MARK: Mapping

    private RideDto toDto(Ride ride, UUID viewer) {
        boolean isDriver = viewer.equals(ride.getDriverUserId());
        WorkerPosition position = ride.getState().isLive() && ride.getDriverWorkerId() != null
            ? dispatch.positionOf(ride.getDriverWorkerId()).orElse(null) : null;
        ProfileDto other = null;
        UUID otherId = isDriver ? ride.getRiderId() : ride.getDriverUserId();
        if (otherId != null) other = profiles.findById(otherId).orElse(null);
        boolean ratingsOut = ride.ratingsVisibleTo(viewer);
        return new RideDto(ride.getId(), ride.getState().name(), ride.getCategory(),
            ride.getPickupLabel(), ride.getPickupLatitude(), ride.getPickupLongitude(),
            ride.getDropoffLabel(), ride.getDropoffLatitude(), ride.getDropoffLongitude(),
            ride.getNote(), ride.getDistanceMetres(), ride.getDurationSeconds(),
            ride.getSuggestedFareMinor(), ride.getOfferedFareMinor(), ride.getAgreedFareMinor(),
            ride.getCurrency(), ride.getCancelFeeMinor(),
            isDriver ? ride.getTokenCost() : null,
            other == null ? null : other.id(),
            other == null ? null : displayName(other),
            other == null ? null : other.avatarUrl(),
            ride.getVehicleLabel(), ride.getVehiclePlate(), ride.isVehicleVerified(),
            position == null ? null : position.latitude(),
            position == null ? null : position.longitude(),
            position == null ? null : position.at(),
            ride.getConversationId(),
            offers.findByRideIdAndState(ride.getId(), RideOfferState.PENDING).stream()
                .filter(o -> !o.isLapsed(OffsetDateTime.now()))
                .filter(o -> isDriver ? o.getDriverUserId().equals(viewer) : true)
                .map(this::toOfferDto)
                .toList(),
            // Blind until both are in: see Ride.ratingsVisibleTo.
            isDriver ? ride.getRiderRating() : ride.getDriverRating(),
            ratingsOut ? (isDriver ? ride.getDriverRating() : ride.getRiderRating()) : null,
            ride.getSosAt(),
            ride.getExpiresAt(), ride.getRequestedAt(), ride.getConfirmedAt(),
            ride.getStartedAt(), ride.getCompletedAt(), ride.getCancelReason());
    }

    private RideOfferDto toOfferDto(RideOffer offer) {
        ProfileDto driver = profiles.findById(offer.getDriverUserId()).orElse(null);
        return new RideOfferDto(offer.getId(), offer.getRideId(), offer.getParty().name(),
            offer.getAmountMinor(), offer.getRound(), offer.getState().name(),
            offer.getDriverUserId(),
            driver == null ? null : displayName(driver),
            driver == null ? null : driver.avatarUrl(),
            offer.getExpiresAt(), offer.getCreatedAt());
    }
}
