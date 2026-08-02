package com.gojogo.travel.internal;

import com.gojogo.auth.PlatformAdminApi;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Trips somebody raised an alarm on (Phase 3 M5, SPECS §10: "trip flagged SOS —
 * admin surface + event").
 *
 * <p>Guarded exactly like partner review and the moderation queue: the
 * operator's own Cognito account carrying the {@code platform-admin} group, or
 * the break-glass token. A caller with neither gets a 404 — this path does not
 * admit that it exists.
 *
 * <p><strong>Read-only, and that is deliberate.</strong> There is no "resolve"
 * button, because there is no honest thing for one to mean: a trip in trouble is
 * dealt with by a person picking up a phone, not by a status changing in a
 * queue. What this surface owes an operator is the trip, who raised it, and who
 * to call — and it is the queue existing at all that turns a button on a phone
 * into something anybody sees.
 *
 * <pre>
 * curl -H "X-Partner-Admin-Token: $TOKEN" https://api.gojogo.app/v1/travel/admin/sos
 * </pre>
 */
@RestController
class TravelAdminController {

    static final String TOKEN_HEADER = "X-Partner-Admin-Token";

    private final RideService rides;
    private final PlatformAdminApi admins;

    TravelAdminController(RideService rides, PlatformAdminApi admins) {
        this.rides = rides;
        this.admins = admins;
    }

    @GetMapping("/v1/travel/admin/sos")
    List<SosRideDto> sosRides(@RequestHeader(name = TOKEN_HEADER, required = false) String token,
                              @AuthenticationPrincipal Jwt jwt,
                              @RequestParam(defaultValue = "50") int limit) {
        admins.require(token, jwt);
        return rides.sosRides(limit);
    }
}
