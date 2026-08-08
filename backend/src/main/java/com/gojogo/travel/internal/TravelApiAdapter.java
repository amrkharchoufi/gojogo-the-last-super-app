package com.gojogo.travel.internal;

import com.gojogo.travel.TravelApi;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * {@link TravelApi} over {@link RideService} — the same pricing engine and the
 * same live-ride lookup the rider's own screens use.
 */
@Component
class TravelApiAdapter implements TravelApi {

    private final RideService rides;

    TravelApiAdapter(RideService rides) {
        this.rides = rides;
    }

    @Override
    public Quote quote(double pickupLatitude, double pickupLongitude,
                       double dropoffLatitude, double dropoffLongitude) {
        QuoteResponse quoted = rides.quote(new QuoteRequest(pickupLatitude, pickupLongitude,
            dropoffLatitude, dropoffLongitude));
        List<QuotedCategory> categories = quoted.categories().stream()
            .map(c -> new QuotedCategory(c.category(), c.suggestedFareMinor(), c.minimumMinor()))
            .toList();
        return new Quote(quoted.distanceMetres(), quoted.durationSeconds(), quoted.currency(),
            categories);
    }

    @Override
    public Optional<Ride> currentRide(UUID userId, boolean includeRecent) {
        Optional<RideDto> live = rides.liveFor(userId);
        if (live.isEmpty() && includeRecent) {
            live = rides.history(userId, 1).stream().findFirst();
        }
        return live.map(TravelApiAdapter::toRide);
    }

    private static Ride toRide(RideDto r) {
        return new Ride(r.id(), r.state(), r.category(), r.pickupLabel(), r.dropoffLabel(),
            r.suggestedFareMinor(), r.agreedFareMinor(), r.currency(),
            r.otherPartyName(), r.vehicleLabel(), r.distanceMetres(), r.durationSeconds());
    }
}
