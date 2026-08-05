package com.gojogo.delivery.internal;

import com.gojogo.auth.AdminActor;
import com.gojogo.auth.PlatformAdminApi;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * Reporting a problem with a delivered order, and answering one (Phase 4 M6).
 *
 * <p>Two controllers in one file because they are two ends of the same
 * conversation, and reading them apart is how the customer's side and the
 * operator's side drift into describing different things.
 */
@RestController
class DisputeController {

    private final DisputeService disputes;
    private final DeliveryCurrentProfile current;

    DisputeController(DisputeService disputes, DeliveryCurrentProfile current) {
        this.disputes = disputes;
        this.current = current;
    }

    /**
     * Reports a problem. <b>409</b> when the order is not delivered, is outside
     * the configured window, or already has a report — one per order, because
     * two open reports on one order is two operators refunding the same missing
     * pizza.
     */
    @PostMapping("/v1/delivery/orders/{orderId}/dispute")
    @ResponseStatus(HttpStatus.CREATED)
    DisputeDto file(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID orderId,
                    @Valid @RequestBody FileDisputeRequest request) {
        return disputes.file(current.require(jwt).id(), orderId, request);
    }

    /** The report on this order, or {@code null}. */
    @GetMapping("/v1/delivery/orders/{orderId}/dispute")
    DisputeDto mine(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID orderId) {
        return disputes.mine(current.require(jwt).id(), orderId);
    }

    /** A presigned PUT for a photo of what arrived. The server mints the key
     *  and stamps it on the report; no endpoint here accepts one. */
    @PostMapping("/v1/delivery/orders/{orderId}/dispute/photo")
    ProofUploadDto photo(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID orderId) {
        return disputes.photoUpload(current.require(jwt).id(), orderId);
    }
}

/**
 * The operator's queue.
 *
 * <p>Gated exactly like the moderation queue — the `platform-admin` Cognito
 * group or the break-glass token, through the one definition of "is this caller
 * an operator" that {@code auth} has owned since 2e M5. A refund moves real
 * money, so it must not be reachable by anybody a report is about.
 *
 * <p><b>Nothing here happens on its own.</b> No auto-refund under a threshold,
 * no timer that resolves a stale report, no scoring. This is a queue that piles
 * up until a person opens it, exactly like the KYC and moderation ones, and
 * that is a staffing fact rather than a missing feature.
 */
@RestController
class DisputeAdminController {

    static final String TOKEN_HEADER = "X-Partner-Admin-Token";

    private final DisputeService disputes;
    private final PlatformAdminApi admins;

    DisputeAdminController(DisputeService disputes, PlatformAdminApi admins) {
        this.disputes = disputes;
        this.admins = admins;
    }

    @GetMapping("/v1/delivery/admin/disputes")
    List<AdminDisputeDto> queue(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false) String state,
            @RequestParam(defaultValue = "50") int limit) {
        admins.require(token, jwt);
        return disputes.queue(state, limit);
    }

    @GetMapping("/v1/delivery/admin/disputes/{disputeId}")
    AdminDisputeDto one(@RequestHeader(name = TOKEN_HEADER, required = false) String token,
                        @AuthenticationPrincipal Jwt jwt,
                        @PathVariable UUID disputeId) {
        admins.require(token, jwt);
        return disputes.get(disputeId);
    }

    /**
     * Sends money back out of a named party's earnings on the order.
     *
     * <p><b>409</b> with the number, three ways: over what that party was paid
     * for this order, over what the customer paid in total, or over what the
     * payer can currently cover. The last one is the interesting refusal — a
     * restaurant that has already withdrawn genuinely cannot fund this, and
     * quietly moving the cost to the platform would be deciding on somebody's
     * behalf that the platform absorbs every kitchen's mistakes.
     */
    @PostMapping("/v1/delivery/admin/disputes/{disputeId}/refund")
    AdminDisputeDto refund(@RequestHeader(name = TOKEN_HEADER, required = false) String token,
                           @AuthenticationPrincipal Jwt jwt,
                           @PathVariable UUID disputeId,
                           @Valid @RequestBody ResolveDisputeRequest request) {
        AdminActor actor = admins.require(token, jwt);
        return disputes.refund(disputeId, request.refundCents(), request.payer(),
            request.note(), actor.toString());
    }

    /** Refuses it, in words the customer reads. The note is what stops a
     *  rejection being indistinguishable from nobody looking. */
    @PostMapping("/v1/delivery/admin/disputes/{disputeId}/reject")
    AdminDisputeDto reject(@RequestHeader(name = TOKEN_HEADER, required = false) String token,
                           @AuthenticationPrincipal Jwt jwt,
                           @PathVariable UUID disputeId,
                           @Valid @RequestBody(required = false) ResolveDisputeRequest request) {
        AdminActor actor = admins.require(token, jwt);
        return disputes.reject(disputeId, request == null ? null : request.note(),
            actor.toString());
    }
}
