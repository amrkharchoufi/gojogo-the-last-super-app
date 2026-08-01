package com.gojogo.dispatch.internal;

import com.gojogo.dispatch.WorkerKind;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.EnumSet;
import java.util.UUID;

/**
 * The worker's side of dispatch — the only REST surface this module has.
 *
 * <p>There is deliberately no customer-facing endpoint here. A rider does not
 * talk to dispatch; they talk to {@code travel}, which asks dispatch on their
 * behalf, and a customer surface would give the module a second set of callers
 * with a completely different idea of what a "job" is.
 *
 * <p><b>Positions arrive over REST, not the WebSocket</b>, and that is a
 * deviation from SPECS §3 worth naming. The socket that exists is API Gateway
 * with {@code $connect}/{@code $disconnect} Lambdas owning a connection registry
 * — there is no inbound message route, and building one belongs in the milestone
 * where positions are actually <em>watched</em> (M3's live trip), not in the one
 * where they are merely stored. A POST every five seconds while available costs a
 * request each and is trivially correct.
 *
 * <pre>
 * # what am I, and what's on my screen
 * curl -H "Authorization: Bearer $JWT" https://api.gojogo.app/v1/dispatch/me
 *
 * # sign on, then keep saying where you are
 * curl -X POST -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
 *   -d '{"kind":"DRIVER","available":true}' \
 *   https://api.gojogo.app/v1/dispatch/me/availability
 * curl -X POST -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
 *   -d '{"latitude":33.5731,"longitude":-7.5898}' \
 *   https://api.gojogo.app/v1/dispatch/me/position
 *
 * # take it, or don't
 * curl -X POST -H "Authorization: Bearer $JWT" \
 *   https://api.gojogo.app/v1/dispatch/offers/$OFFER_ID/accept
 * </pre>
 */
@RestController
class DispatchController {

    private final DispatchService dispatch;
    private final DispatchCurrentProfile current;

    DispatchController(DispatchService dispatch, DispatchCurrentProfile current) {
        this.dispatch = dispatch;
        this.current = current;
    }

    /**
     * Everything at once. One call rather than four, because a driver's app opens
     * to a screen that needs all of it and a phone on a motorbike should make as
     * few round trips as it can.
     *
     * <p>Answers for anybody signed in, with empty lists for somebody who has
     * never been approved — not a 404. "Are you a driver" is a question the app
     * asks before it knows, and a missing resource is the wrong way to say no.
     */
    @GetMapping("/v1/dispatch/me")
    MyDispatchResponse mine(@AuthenticationPrincipal Jwt jwt) {
        return dispatch.mine(current.require(jwt).id());
    }

    @PostMapping("/v1/dispatch/me/availability")
    WorkerDto availability(@AuthenticationPrincipal Jwt jwt,
                           @Valid @RequestBody AvailabilityRequest request) {
        return dispatch.setAvailability(current.require(jwt).id(),
            parseKind(request.kind()), request.available());
    }

    /**
     * Where they are. 204 and no body on purpose: this is the highest-frequency
     * call in the system by an order of magnitude, and returning state a client
     * did not ask for would multiply that by whatever the state costs to build.
     */
    @PostMapping("/v1/dispatch/me/position")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void position(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody PositionRequest request) {
        dispatch.reportPosition(current.require(jwt).id(),
            request.latitude(), request.longitude());
    }

    @PostMapping("/v1/dispatch/offers/{offerId}/accept")
    AssignmentDto accept(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID offerId) {
        return dispatch.accept(current.require(jwt).id(), offerId);
    }

    @PostMapping("/v1/dispatch/offers/{offerId}/decline")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void decline(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID offerId) {
        dispatch.decline(current.require(jwt).id(), offerId);
    }

    private static WorkerKind parseKind(String name) {
        try {
            return WorkerKind.valueOf(name.trim().toUpperCase());
        } catch (RuntimeException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Unknown worker kind; use one of " + EnumSet.allOf(WorkerKind.class));
        }
    }
}
