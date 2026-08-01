package com.gojogo.travel.internal;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * GojoTravel's REST surface — both sides of it.
 *
 * <p>Rider and driver share one controller because they share one object: the
 * ride. Splitting them would mean two paths to the same row and two places to
 * get the authorisation wrong. Every endpoint resolves who is calling and the
 * service decides what that makes them; somebody who is neither party gets a 404
 * rather than a 403, because whether a stranger's trip exists is not their
 * business.
 *
 * <pre>
 * # what would it cost — every category at once
 * curl -X POST -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
 *   -d '{"pickupLatitude":33.5731,"pickupLongitude":-7.5898,
 *        "dropoffLatitude":33.5892,"dropoffLongitude":-7.6031}' \
 *   https://api.gojogo.app/v1/travel/quote
 *
 * # ask, at the suggested price or your own
 * curl -X POST -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
 *   -d '{"category":"CAR","pickupLatitude":33.5731,"pickupLongitude":-7.5898,
 *        "pickupLabel":"Bd d'\''Anfa","dropoffLatitude":33.5892,
 *        "dropoffLongitude":-7.6031,"dropoffLabel":"Maarif","offeredFareMinor":900}' \
 *   https://api.gojogo.app/v1/travel/rides
 *
 * # a driver wants more; the rider takes it
 * curl -X POST -H "Authorization: Bearer $DRIVER_JWT" -H 'Content-Type: application/json' \
 *   -d '{"amountMinor":1200}' \
 *   https://api.gojogo.app/v1/travel/rides/$RIDE/offers
 * curl -X POST -H "Authorization: Bearer $JWT" \
 *   https://api.gojogo.app/v1/travel/rides/$RIDE/offers/$OFFER/accept
 * </pre>
 */
@RestController
class TravelController {

    private final RideService rides;
    private final TravelCurrentProfile current;

    TravelController(RideService rides, TravelCurrentProfile current) {
        this.rides = rides;
        this.current = current;
    }

    // MARK: The rider

    @PostMapping("/v1/travel/quote")
    QuoteResponse quote(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody QuoteRequest body) {
        current.require(jwt);
        return rides.quote(body);
    }

    @PostMapping("/v1/travel/rides")
    @ResponseStatus(HttpStatus.CREATED)
    RideDto request(@AuthenticationPrincipal Jwt jwt,
                    @Valid @RequestBody RequestRideRequest body) {
        return rides.request(current.require(jwt).id(), body);
    }

    /**
     * The one ride in progress, from whichever side the caller is on.
     * {@code {"ride": null}} rather than a 404 — "am I in a car" is a question
     * the app asks before it knows.
     */
    @GetMapping("/v1/travel/rides/live")
    MyRideResponse live(@AuthenticationPrincipal Jwt jwt) {
        return new MyRideResponse(rides.liveFor(current.require(jwt).id()).orElse(null));
    }

    @GetMapping("/v1/travel/rides")
    List<RideDto> history(@AuthenticationPrincipal Jwt jwt,
                          @RequestParam(defaultValue = "20") int limit) {
        return rides.history(current.require(jwt).id(), limit);
    }

    @GetMapping("/v1/travel/rides/{rideId}")
    RideDto get(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID rideId) {
        return rides.get(current.require(jwt).id(), rideId);
    }

    /** Take a driver's price. */
    @PostMapping("/v1/travel/rides/{rideId}/offers/{offerId}/accept")
    RideDto acceptOffer(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID rideId,
                        @PathVariable UUID offerId) {
        return rides.acceptAsRider(current.require(jwt).id(), rideId, offerId);
    }

    @PostMapping("/v1/travel/rides/{rideId}/offers/{offerId}/decline")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void declineOffer(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID rideId,
                      @PathVariable UUID offerId) {
        rides.declineOffer(current.require(jwt).id(), rideId, offerId);
    }

    /** One more round, addressed to that driver and nobody else. */
    @PostMapping("/v1/travel/rides/{rideId}/offers/{offerId}/counter")
    RideOfferDto counterBack(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID rideId,
                             @PathVariable UUID offerId,
                             @Valid @RequestBody OfferAmountRequest body) {
        return rides.counterBack(current.require(jwt).id(), rideId, offerId, body.amountMinor());
    }

    // MARK: The driver

    /**
     * Ride tokens: what the caller holds, what a trip costs, and — when they
     * cannot work — the sentence that says so (Phase 3 M4).
     *
     * <p>Here rather than on {@code /v1/payments/tokens} because only this
     * module knows what a ride costs. Payments sells tokens; travel says what
     * they buy, and is therefore the only module that can turn "no work is
     * arriving" into a reason. Being filtered out of dispatch is otherwise
     * completely silent, which reads as a broken app.
     */
    @GetMapping("/v1/travel/tokens")
    MyRideTokensDto myTokens(@AuthenticationPrincipal Jwt jwt) {
        return rides.myTokens(current.require(jwt).id());
    }

    /** Prices this driver has on the table, across every ride. */
    @GetMapping("/v1/travel/driver/offers")
    List<RideOfferDto> myOffers(@AuthenticationPrincipal Jwt jwt) {
        return rides.myOffers(current.require(jwt).id());
    }

    /**
     * "Not at that price." Posting one is also a decline of the dispatch offer —
     * a driver who wants a different fare is answering no to the question
     * dispatch asked.
     */
    @PostMapping("/v1/travel/rides/{rideId}/offers")
    @ResponseStatus(HttpStatus.CREATED)
    RideOfferDto counter(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID rideId,
                         @Valid @RequestBody OfferAmountRequest body) {
        return rides.counter(current.require(jwt).id(), rideId, body.amountMinor());
    }

    /** The driver takes the rider's counter. */
    @PostMapping("/v1/travel/rides/{rideId}/offers/{offerId}/take")
    RideDto takeOffer(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID rideId,
                      @PathVariable UUID offerId) {
        return rides.acceptAsDriver(current.require(jwt).id(), rideId, offerId);
    }

    @PostMapping("/v1/travel/rides/{rideId}/arriving")
    RideDto arriving(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID rideId) {
        return rides.driverArriving(current.require(jwt).id(), rideId);
    }

    @PostMapping("/v1/travel/rides/{rideId}/start")
    RideDto start(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID rideId) {
        return rides.startTrip(current.require(jwt).id(), rideId);
    }

    /** Ends the trip and moves the money — one transfer, no commission. */
    @PostMapping("/v1/travel/rides/{rideId}/complete")
    RideDto complete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID rideId) {
        return rides.complete(current.require(jwt).id(), rideId);
    }

    // MARK: Either side

    @PostMapping("/v1/travel/rides/{rideId}/cancel")
    RideDto cancel(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID rideId,
                   @RequestBody(required = false) CancelRideRequest body) {
        return rides.cancel(current.require(jwt).id(), rideId,
            body == null ? null : body.reason());
    }

    @PostMapping("/v1/travel/rides/{rideId}/rate")
    RideDto rate(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID rideId,
                 @Valid @RequestBody RateRideRequest body) {
        return rides.rate(current.require(jwt).id(), rideId, body.stars());
    }
}
