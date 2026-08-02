package com.gojogo.partner.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.partner.VehicleVerificationInvited;
import com.gojogo.payments.AccountRef;
import com.gojogo.payments.Bucket;
import com.gojogo.payments.InsufficientFundsException;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.WalletApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Community vehicle verification (SPECS §4) — the passengers check the car.
 *
 * <p>The mechanism the vision names, and the reason the $30 stake exists at all:
 * a driver locks up their own money, and it is out of that money that the people
 * who ride with them are paid to confirm the car is what the papers said. A
 * reviewer looked at a photograph of a registration document; a passenger looked
 * at the actual car with the actual driver in it, which is the only check that
 * catches a swapped plate.
 *
 * <p>Four decisions carry it:
 *
 * <ul>
 *   <li><strong>The first completed trip asks, and only the first.</strong> One
 *       invitation per trip and at most one live at a time — a car that asked
 *       every passenger would be a car whose badge means "somebody eventually
 *       said yes". A lapsed invitation falls through to the next trip's
 *       passenger, up to a configured cap, after which the vehicle simply stays
 *       APPROVED. That is not a failure state: APPROVED is already roadworthy,
 *       and the badge is a bonus.</li>
 *   <li><strong>All five answers, or none.</strong> Each question is a different
 *       way the car could be wrong; a badge that survives one "no" says nothing.
 *       Silence is neither — an expired invitation flags nothing, because a
 *       passenger who never opened the app has made no accusation.</li>
 *   <li><strong>A "no" flags the vehicle and suspends the driver</strong>, in one
 *       transaction. A flag that leaves work arriving is a flag that did nothing,
 *       which is exactly the rule the papers-expiry sweep already follows.</li>
 *   <li><strong>The reward is a transfer, not an invention.</strong> STAKING →
 *       the passenger's REWARDS, capped at what is left of the stake, and
 *       recorded on the application so a later release does not hand back money
 *       that is already gone.</li>
 * </ul>
 */
@Service
class VehicleVerificationService {

    private static final Logger log = LoggerFactory.getLogger(VehicleVerificationService.class);

    private final VehicleVerificationRepository verifications;
    private final VehicleRepository vehicles;
    private final PartnerAccountRepository accounts;
    private final PartnerService partners;
    private final WalletApi wallet;
    private final ProfileApi profiles;
    private final ConfigApi config;
    private final ApplicationEventPublisher events;

    VehicleVerificationService(VehicleVerificationRepository verifications,
                               VehicleRepository vehicles, PartnerAccountRepository accounts,
                               PartnerService partners, WalletApi wallet, ProfileApi profiles,
                               ConfigApi config, ApplicationEventPublisher events) {
        this.verifications = verifications;
        this.vehicles = vehicles;
        this.accounts = accounts;
        this.partners = partners;
        this.wallet = wallet;
        this.profiles = profiles;
        this.config = config;
        this.events = events;
    }

    // MARK: The invitation

    /**
     * A trip finished — ask this passenger about the car, if this car still
     * needs asking about.
     *
     * <p><strong>{@code REQUIRES_NEW}, and it is load-bearing.</strong> This runs
     * from an {@code AFTER_COMMIT} listener, where the just-committed
     * transaction's resources are still bound to the thread: plain
     * {@code REQUIRED} joins a transaction that is already finished and the
     * first flush throws "no transaction is in progress". Learned the expensive
     * way in production on 2026-08-01 (see PROGRESS's incident log), and the
     * shape is identical here.
     *
     * <p>Every refusal below is silent, which is right: none of them is anything
     * a rider did, and a trip that ends with an unexplained error message is
     * worse than one that ends.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void inviteFromTrip(UUID rideId, UUID passengerId, UUID driverUserId, UUID vehicleId) {
        if (vehicleId == null || passengerId == null) return;
        Vehicle vehicle = vehicles.findById(vehicleId).orElse(null);
        // APPROVED and not yet verified is the only state worth asking about. A
        // vehicle already carrying the badge has nothing to earn, and a flagged
        // one has a human looking at it.
        if (vehicle == null || vehicle.getState() != VehicleState.APPROVED) return;
        // The driver cannot verify their own car, and neither can somebody who
        // already answered about it: the second is how one friend's five trips
        // become a badge.
        if (passengerId.equals(driverUserId)) return;
        OffsetDateTime now = OffsetDateTime.now();
        List<VehicleVerification> history = verifications
            .findByVehicleIdOrderByCreatedAtDesc(vehicleId);
        if (history.stream().anyMatch(v -> v.isOpen(now))) return;
        if (history.size() >= maxInvites()) return;
        if (history.stream().anyMatch(v -> v.getPassengerId().equals(passengerId))) return;

        PartnerAccount account = accounts.findById(vehicle.getAccountId()).orElse(null);
        if (account == null || account.getStatus() != PartnerStatus.APPROVED) return;

        VehicleVerification invitation;
        try {
            invitation = verifications.saveAndFlush(new VehicleVerification(vehicleId,
                account.getId(), passengerId, driverUserId, rideId,
                now.plusHours(inviteTtlHours())));
        } catch (DataIntegrityViolationException alreadyAsked) {
            // The unique index on the ride caught a redelivered event. Exactly
            // what it is for.
            return;
        }
        events.publishEvent(new VehicleVerificationInvited(invitation.getId(), passengerId,
            vehicleId, firstName(driverUserId), describe(vehicle), vehicle.getPlate(),
            rewardMinor(), wallet.currency(), invitation.getExpiresAt()));
        log.info("Asked passenger {} to verify vehicle {} after ride {}",
            passengerId, vehicleId, rideId);
    }

    // MARK: The passenger's answer

    @Transactional(readOnly = true)
    List<VerificationInviteDto> myInvitations(UUID passengerId) {
        OffsetDateTime now = OffsetDateTime.now();
        return verifications.findByPassengerIdOrderByCreatedAtDesc(passengerId).stream()
            .filter(v -> v.isOpen(now))
            .map(this::toInviteDto)
            .toList();
    }

    /**
     * The passenger answers, and this is where a badge or a flag comes from.
     *
     * <p>The reward is paid <em>after</em> the vehicle is marked, and a failure
     * to pay it does not undo the verification: the car is either what it says
     * it is or it is not, and that fact should not depend on a driver's stake
     * having survived their ID check.
     */
    @Transactional
    VerificationInviteDto answer(UUID passengerId, UUID verificationId,
                                 AnswerVerificationRequest request) {
        VehicleVerification invitation = verifications.findById(verificationId)
            .filter(v -> v.getPassengerId().equals(passengerId))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such verification"));
        if (!invitation.isOpen(OffsetDateTime.now())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                invitation.getStatus() == VerificationStatus.PENDING
                    ? "That request has expired"
                    : "You've already answered this one");
        }
        invitation.answer(bool(request.driverMatched()), bool(request.photosMatched()),
            bool(request.plateMatched()), bool(request.roadworthy()), bool(request.noFraud()),
            request.comment());

        Vehicle vehicle = vehicles.findById(invitation.getVehicleId()).orElse(null);
        PartnerAccount account = accounts.findById(invitation.getAccountId()).orElse(null);
        if (vehicle == null || account == null) {
            // The car was retired between the trip and the answer. The row keeps
            // the answer; there is nothing left to mark.
            verifications.flush();
            return toInviteDto(invitation);
        }
        if (invitation.allYes()) {
            confirm(invitation, vehicle, account);
        } else {
            reject(invitation, vehicle, account);
        }
        verifications.flush();
        return toInviteDto(invitation);
    }

    private void confirm(VehicleVerification invitation, Vehicle vehicle,
                         PartnerAccount account) {
        vehicle.markCommunityVerified();
        vehicles.flush();
        // The badge is one of the things dispatch carries, so it goes down the
        // same way a plate does — pushed, never read across.
        partners.pushVehicleToDispatch(account);
        payReward(invitation, account);
        log.info("Vehicle {} community-verified by passenger {}", vehicle.getId(),
            invitation.getPassengerId());
    }

    private void reject(VehicleVerification invitation, Vehicle vehicle,
                        PartnerAccount account) {
        String note = "A passenger reported that " + invitation.failureSummary()
            + (invitation.getComment().isBlank() ? "" : " — \"" + invitation.getComment() + "\"");
        vehicle.flag(note);
        vehicles.flush();
        // Flagging alone only changes a badge. Taking the driver off the road is
        // what makes this a safety mechanism rather than a survey, and an
        // operator restores them by approving again — exactly as with lapsed
        // papers.
        partners.suspendForVehicle(account, "Your vehicle is under review — " + note);
        log.warn("Vehicle {} flagged by passenger {}: {}", vehicle.getId(),
            invitation.getPassengerId(), invitation.failureSummary());
    }

    /**
     * Pays the passenger out of the driver's own locked stake.
     *
     * <p>Capped at what is left of it, for the same reason the KYC fee is: a
     * config mistake can make the reward useless, but it must never put a stake
     * into debt. A driver with nothing left pays nothing, and the verification
     * still stands — the badge is about the car, not about the balance.
     */
    private void payReward(VehicleVerification invitation, PartnerAccount account) {
        long reward = Math.min(rewardMinor(), account.remainingStakeMinor());
        if (reward <= 0) return;
        try {
            wallet.transfer(
                AccountRef.user(account.getUserId(), Bucket.STAKING),
                AccountRef.user(invitation.getPassengerId(), Bucket.REWARDS),
                reward, LedgerKind.REWARD,
                WalletApi.Reference.of("VEHICLE_VERIFICATION", invitation.getId(),
                    "Thanks for verifying a vehicle"),
                "verification:" + invitation.getId() + ":reward");
            invitation.recordReward(reward);
            account.recordRewardPaid(reward, OffsetDateTime.now());
        } catch (InsufficientFundsException stakeAlreadySpent) {
            // The row said there was enough and the ledger disagreed. Worth a
            // line, and not worth losing the verification over.
            log.warn("Verification {} confirmed but the reward could not be paid: {}",
                invitation.getId(), stakeAlreadySpent.getMessage());
        }
    }

    // MARK: The sweep

    @Transactional(readOnly = true)
    List<UUID> lapsedInvitationIds(int batch) {
        return verifications.lapsed(VerificationStatus.PENDING, OffsetDateTime.now(),
                PageRequest.of(0, batch)).stream()
            .map(VehicleVerification::getId)
            .toList();
    }

    /** Marks one lapsed invitation. Re-checked inside its own transaction: a
     *  passenger may have answered in the seconds since the sweep listed it. */
    @Transactional
    void expireIfStillOpen(UUID verificationId) {
        verifications.findById(verificationId)
            .filter(v -> v.getStatus() == VerificationStatus.PENDING)
            .filter(v -> !v.getExpiresAt().isAfter(OffsetDateTime.now()))
            .ifPresent(VehicleVerification::expire);
    }

    // MARK: Helpers

    long rewardMinor() {
        return Math.max(0, config.number("partner.verification.reward.minor", 300));
    }

    private long inviteTtlHours() {
        return Math.clamp(config.number("partner.verification.invite.ttl.hours", 48), 1, 720);
    }

    private int maxInvites() {
        return (int) Math.clamp(config.number("partner.verification.max.invites", 3), 1, 20);
    }

    private static boolean bool(Boolean value) {
        // A question left out of the body is a question that was not answered
        // yes, which is what "all five or none" has to mean when the client is
        // an older build.
        return Boolean.TRUE.equals(value);
    }

    /** First name only: the passenger is being asked whether the driver matched
     *  the app, and naming them in full answers the question for them. */
    private String firstName(UUID userId) {
        return profiles.findById(userId)
            .map(VehicleVerificationService::displayName)
            .map(name -> name.split("\\s+")[0])
            .orElse("your driver");
    }

    private static String displayName(ProfileDto profile) {
        return profile.displayName() == null || profile.displayName().isBlank()
            ? "@" + profile.handle() : profile.displayName();
    }

    /** {@link VehicleService#describe}, with a fallback: a passenger is being
     *  asked about a car, and "confirm " with nothing after it is not a
     *  question. */
    private static String describe(Vehicle vehicle) {
        String described = VehicleService.describe(vehicle);
        return described.isBlank() ? "the car" : described;
    }

    private VerificationInviteDto toInviteDto(VehicleVerification invitation) {
        Optional<Vehicle> vehicle = vehicles.findById(invitation.getVehicleId());
        return new VerificationInviteDto(invitation.getId(), invitation.getStatus().name(),
            invitation.getVehicleId(),
            vehicle.map(VehicleVerificationService::describe).orElse("the car"),
            vehicle.map(Vehicle::getPlate).orElse(""),
            vehicle.map(v -> v.getYear() == null ? null : v.getYear()).orElse(null),
            firstName(invitation.getDriverUserId()),
            invitation.getRewardMinor() > 0 ? invitation.getRewardMinor() : rewardMinor(),
            wallet.currency(), invitation.getExpiresAt(), invitation.getCreatedAt());
    }
}
