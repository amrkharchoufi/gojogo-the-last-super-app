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
 * The kitchen's screen — the surface {@code MerchantManagementService} said, in
 * as many words, that this product deliberately did not have: <i>"a merchant
 * cannot accept, reject or advance an order, because OrderFulfilmentJob walks
 * every order along a simulated timeline; giving the kitchen a button that the
 * job would immediately overrule is worse than not having one."</i> The job is
 * gone, so the buttons are real.
 *
 * <p>On the owner's own {@code /mine} surface, authorised the same way the menu
 * editor is: the caller must be the merchant's {@code ownerId}, and this module
 * knows nothing about applications or KYC. It is also, per ARCHITECTURE §10b,
 * exactly the surface GoJoAdmin's order screen will call — no admin-only mirror.
 *
 * <pre>
 * curl -H "Authorization: Bearer $JWT" https://api.gojogo.app/v1/delivery/merchants/mine/orders
 * curl -X POST -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
 *   -d '{"prepMinutes":25}' \
 *   https://api.gojogo.app/v1/delivery/merchants/mine/orders/$ORDER/accept
 * curl -X POST -H "Authorization: Bearer $JWT" \
 *   https://api.gojogo.app/v1/delivery/merchants/mine/orders/$ORDER/ready
 * </pre>
 */
@RestController
class MerchantOrderController {

    private final OrderFulfilmentService fulfilment;
    private final DeliveryCurrentProfile current;

    MerchantOrderController(OrderFulfilmentService fulfilment, DeliveryCurrentProfile current) {
        this.fulfilment = fulfilment;
        this.current = current;
    }

    /** Everything still in flight, oldest first. */
    @GetMapping("/v1/delivery/merchants/mine/orders")
    List<MerchantOrderDto> queue(@AuthenticationPrincipal Jwt jwt) {
        return fulfilment.queue(current.require(jwt).id());
    }

    @GetMapping("/v1/delivery/merchants/mine/orders/history")
    List<MerchantOrderDto> history(@AuthenticationPrincipal Jwt jwt,
                                   @RequestParam(defaultValue = "20") int limit) {
        return fulfilment.recent(current.require(jwt).id(), limit);
    }

    /**
     * Takes the order, and starts the clock everything downstream is timed from:
     * the prep estimate decides when a courier is looked for and what the
     * customer's countdown says.
     */
    /* Since Phase 4 M3 the {id} on these three verbs is the sub-order id —
     * one kitchen's slice of a possibly multi-merchant order. The queue above
     * is where clients get the id, so the deployed app needed no change: the
     * id was always opaque to it. */

    @PostMapping("/v1/delivery/merchants/mine/orders/{subOrderId}/accept")
    MerchantOrderDto accept(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID subOrderId,
                            @Valid @RequestBody(required = false) AcceptOrderRequest request) {
        return fulfilment.accept(current.require(jwt).id(), subOrderId,
            request == null ? null : request.prepMinutes());
    }

    /** Only before accepting. Cancels this kitchen's slice and gives the
     *  customer that slice's money back in the same transaction; the rest of
     *  the order, if there is one, carries on. */
    @PostMapping("/v1/delivery/merchants/mine/orders/{subOrderId}/reject")
    MerchantOrderDto reject(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID subOrderId,
                            @Valid @RequestBody(required = false) RejectOrderRequest request) {
        return fulfilment.reject(current.require(jwt).id(), subOrderId,
            request == null ? null : request.reason());
    }

    /** The food is done — sooner or later than they guessed. Does not change any
     *  status; it corrects the time the courier is expecting. */
    @PostMapping("/v1/delivery/merchants/mine/orders/{subOrderId}/ready")
    MerchantOrderDto ready(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID subOrderId) {
        return fulfilment.markReady(current.require(jwt).id(), subOrderId);
    }
}
