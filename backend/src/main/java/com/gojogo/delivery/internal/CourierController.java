package com.gojogo.delivery.internal;

import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * Courier Mode's half of an order.
 *
 * <p>Deliberately small, and the reason is the module boundary. Going online,
 * reporting a position, seeing an offer and accepting it are <b>dispatch's</b>
 * surface ({@code /v1/dispatch/**}) and are identical for a driver and a
 * courier — a courier does not get a second copy of them any more than a driver
 * got one. What is left here is the two things that are about a <em>delivery</em>
 * rather than about a job: I have the food, and I have handed it over.
 *
 * <p>The same split {@code travel} made, and the reason a dual-mode person works
 * at all: one registry, one presence, one offer book, and each vertical owning
 * only what its own work means.
 *
 * <p><b>Both verbs answer with a {@link HandoffResultDto} and a 200, whether or
 * not the code was right</b> (Phase 4 M2). That is the one breaking change in
 * this milestone — they used to return the job — and it is deliberate: a
 * courier at a door who typed a 7 for a 1 has not made a bad request, and a 4xx
 * would put an error banner in front of somebody holding a bag of food. A
 * refusal is an answer, with the message to show and the attempts that are left.
 *
 * <pre>
 * curl -H "Authorization: Bearer $JWT" https://api.gojogo.app/v1/delivery/courier/job
 * curl -X POST -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
 *   -d '{"pickupCode":"482913"}' \
 *   https://api.gojogo.app/v1/delivery/courier/orders/$ORDER/picked-up
 * curl -X POST -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
 *   -d '{"pin":"901224"}' \
 *   https://api.gojogo.app/v1/delivery/courier/orders/$ORDER/delivered
 * curl -X POST -H "Authorization: Bearer $JWT" \
 *   https://api.gojogo.app/v1/delivery/courier/orders/$ORDER/proof-photo
 * </pre>
 */
@RestController
class CourierController {

    private final OrderFulfilmentService fulfilment;
    private final DeliveryCurrentProfile current;

    CourierController(OrderFulfilmentService fulfilment, DeliveryCurrentProfile current) {
        this.fulfilment = fulfilment;
        this.current = current;
    }

    /**
     * What they are carrying, or {@code {"job": null}}. A 200 rather than a 404
     * for the same reason {@code /v1/dispatch/me} answers for somebody who has
     * never been approved: "nothing right now" is the normal state of a courier
     * who is working, and a missing resource is the wrong way to say it.
     */
    @GetMapping("/v1/delivery/courier/job")
    CourierJobResponse job(@AuthenticationPrincipal Jwt jwt) {
        return fulfilment.job(current.require(jwt).id());
    }

    /** What they have delivered, newest first — the history behind the earnings
     *  on their wallet. */
    @GetMapping("/v1/delivery/courier/deliveries")
    List<CourierJobDto> deliveries(@AuthenticationPrincipal Jwt jwt,
                                   @RequestParam(defaultValue = "20") int limit) {
        return fulfilment.deliveries(current.require(jwt).id(), limit);
    }

    /**
     * They have the food, and typed the code off the restaurant's screen. From
     * here the customer can no longer cancel.
     *
     * <p>The body is optional so that an order minted before {@code V38} — which
     * has no code for anybody to read out — can still be collected with an empty
     * POST, exactly as it could yesterday.
     */
    @PostMapping("/v1/delivery/courier/orders/{orderId}/picked-up")
    HandoffResultDto pickedUp(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID orderId,
                              @Valid @RequestBody(required = false) PickupHandoffRequest request) {
        return fulfilment.pickedUp(current.require(jwt).id(), orderId,
            request == null ? null : request.pickupCode());
    }

    /**
     * Handed over. Settles the order and frees them for the next offer.
     *
     * <p>What has to be in the body depends on how the customer asked for it:
     * the PIN they read out, nothing at all for a contactless drop-off (where
     * the photo has to be up first) or for a plain confirm.
     */
    @PostMapping("/v1/delivery/courier/orders/{orderId}/delivered")
    HandoffResultDto delivered(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID orderId,
                               @Valid @RequestBody(required = false) DeliveryHandoffRequest request) {
        return fulfilment.delivered(current.require(jwt).id(), orderId,
            request == null ? null : request.pin());
    }

    /**
     * A presigned PUT for a photo of the drop-off, for a contactless handoff or
     * for the fallback after a PIN has been missed too many times.
     *
     * <p>There is no matching "attach": the key is stamped on the order in this
     * same call, because the server minted it and therefore already knows it.
     * Nothing here or anywhere else accepts a key from a client.
     */
    @PostMapping("/v1/delivery/courier/orders/{orderId}/proof-photo")
    ProofUploadDto proofPhoto(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID orderId) {
        return fulfilment.proofPhotoUpload(current.require(jwt).id(), orderId);
    }
}
