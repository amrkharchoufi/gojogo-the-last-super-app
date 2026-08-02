package com.gojogo.delivery.internal;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
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
 * <pre>
 * curl -H "Authorization: Bearer $JWT" https://api.gojogo.app/v1/delivery/courier/job
 * curl -X POST -H "Authorization: Bearer $JWT" \
 *   https://api.gojogo.app/v1/delivery/courier/orders/$ORDER/picked-up
 * curl -X POST -H "Authorization: Bearer $JWT" \
 *   https://api.gojogo.app/v1/delivery/courier/orders/$ORDER/delivered
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

    /** They have the food. From here the customer can no longer cancel. */
    @PostMapping("/v1/delivery/courier/orders/{orderId}/picked-up")
    CourierJobDto pickedUp(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID orderId) {
        return fulfilment.pickedUp(current.require(jwt).id(), orderId);
    }

    /** Handed over. Settles the order and frees them for the next offer. */
    @PostMapping("/v1/delivery/courier/orders/{orderId}/delivered")
    CourierJobDto delivered(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID orderId) {
        return fulfilment.delivered(current.require(jwt).id(), orderId);
    }
}
