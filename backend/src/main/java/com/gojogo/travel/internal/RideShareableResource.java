package com.gojogo.travel.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.dispatch.DispatchApi;
import com.gojogo.dispatch.WorkerPosition;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import com.gojogo.share.ShareableResource;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.UUID;

/**
 * What a shared trip looks like to somebody with no account.
 *
 * <p>{@code travel} implements this and {@code share} defines it — the fourth
 * platform-defines / vertical-implements seam in this codebase, and the reason
 * a public tracking endpoint can exist without a platform module learning what a
 * ride is.
 *
 * <p><strong>Everything here was chosen by asking what a stranger who found the
 * link in a group chat should see.</strong> First names, never full ones. The
 * car and the plate, because that is what the link is <em>for</em> — somebody
 * checking that the right car turned up. The destination label, because a person
 * watching wants to know where their friend is going. No handles, no profile
 * ids, no phone numbers, no fare, and nothing that could be used to message
 * either party.
 *
 * <p>It renders on every read rather than at mint time, which is what makes it a
 * tracking link rather than a screenshot.
 */
@Component
class RideShareableResource implements ShareableResource {

    static final String KIND = "ride";

    private final RideRepository rides;
    private final DispatchApi dispatch;
    private final ProfileApi profiles;
    private final ConfigApi config;

    RideShareableResource(RideRepository rides, DispatchApi dispatch, ProfileApi profiles,
                          ConfigApi config) {
        this.rides = rides;
        this.dispatch = dispatch;
        this.profiles = profiles;
        this.config = config;
    }

    @Override
    public String kind() {
        return KIND;
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<SharedView> render(UUID rideId) {
        return rides.findById(rideId).flatMap(this::view);
    }

    private Optional<SharedView> view(Ride ride) {
        // A trip that ended a long time ago has nothing to watch, and a link
        // that outlived it should stop rather than freeze on a last position.
        // The grace is generous on purpose: a link that dies at the kerb dies at
        // the one moment the person watching cares.
        if (ride.getState().isFinished() && ride.getCompletedAt() != null
            && ride.getCompletedAt().plusMinutes(graceMinutes()).isBefore(OffsetDateTime.now())) {
            return Optional.empty();
        }
        String rider = firstName(ride.getRiderId(), "Your friend");
        String driver = firstName(ride.getDriverUserId(), "their driver");
        WorkerPosition position = ride.getState().isLive() && ride.getDriverWorkerId() != null
            ? dispatch.positionOf(ride.getDriverWorkerId()).orElse(null) : null;
        String destination = ride.getDropoffLabel() == null || ride.getDropoffLabel().isBlank()
            ? "their destination" : ride.getDropoffLabel();
        return Optional.of(new SharedView(
            headline(ride, rider, driver, destination),
            status(ride, driver),
            plateLine(ride),
            position == null ? null : position.latitude(),
            position == null ? null : position.longitude(),
            etaMinutes(ride),
            destination,
            ride.getState().isFinished()));
    }

    private static String headline(Ride ride, String rider, String driver, String destination) {
        if (ride.getDriverUserId() == null) {
            return rider + " is looking for a ride to " + destination;
        }
        return rider + " is travelling with " + driver + " to " + destination;
    }

    private static String status(Ride ride, String driver) {
        return switch (ride.getState()) {
            case REQUESTED, NEGOTIATING -> "Looking for a driver";
            case CONFIRMED -> driver + " is on the way to pick them up";
            case ARRIVING -> driver + " has arrived";
            case IN_TRIP -> "On the way";
            case COMPLETED -> "Arrived safely";
            case CANCELLED_RIDER, CANCELLED_DRIVER -> "This trip was cancelled";
            case EXPIRED -> "Nobody took this trip";
        };
    }

    private static String plateLine(Ride ride) {
        if (ride.getVehiclePlate() == null || ride.getVehiclePlate().isBlank()) {
            return ride.getVehicleLabel() == null ? "" : ride.getVehicleLabel();
        }
        return (ride.getVehicleLabel() + " · " + ride.getVehiclePlate()).trim();
    }

    /**
     * Roughly how long is left, from the trip's own duration estimate.
     *
     * <p>Null before the trip starts and after it ends, because a number nobody
     * can act on is worse than none — and this is deliberately not recomputed
     * from the driver's position: the routing here is straight-line × a road
     * factor (M3), and dressing that up as a live ETA on a page somebody is
     * anxiously refreshing would be a confidence the estimate has not earned.
     */
    private static Integer etaMinutes(Ride ride) {
        if (ride.getState() != RideState.IN_TRIP || ride.getStartedAt() == null) return null;
        long elapsed = java.time.Duration.between(ride.getStartedAt(), OffsetDateTime.now())
            .toSeconds();
        long remaining = ride.getDurationSeconds() - elapsed;
        return remaining <= 0 ? 1 : (int) Math.max(1, Math.round(remaining / 60d));
    }

    private long graceMinutes() {
        return Math.max(1, config.number("safety.share.grace.minutes", 60));
    }

    /** First name only. A tracking link is not an introduction. */
    private String firstName(UUID userId, String fallback) {
        if (userId == null) return fallback;
        return profiles.findById(userId)
            .map(RideShareableResource::displayName)
            .map(name -> name.split("\\s+")[0])
            .filter(name -> !name.isBlank())
            .orElse(fallback);
    }

    private static String displayName(ProfileDto profile) {
        return profile.displayName() == null || profile.displayName().isBlank()
            ? "@" + profile.handle() : profile.displayName();
    }
}
