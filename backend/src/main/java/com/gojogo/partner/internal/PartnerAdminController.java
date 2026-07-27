package com.gojogo.partner.internal;

import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.UUID;

/**
 * The review queue. Approving a partner is a human decision about identity
 * documents, and this app has no admin role to hang it on — so, like the
 * economy cleanup endpoints, this surface sits outside the JWT chain and guards
 * itself with a shared token, answering 404 to anyone who doesn't hold it.
 *
 * <p>Nothing here auto-approves and nothing is scheduled: KYC a machine waves
 * through is not KYC. Set {@code PARTNER_ADMIN_TOKEN} (24+ characters) to work
 * the queue.
 *
 * <pre>
 * # who's waiting
 * curl -H "X-Partner-Admin-Token: $TOKEN" \
 *   https://api.gojogo.app/v1/partner/admin/applications
 *
 * # read one, with 10-minute signed links to their papers
 * curl -H "X-Partner-Admin-Token: $TOKEN" \
 *   https://api.gojogo.app/v1/partner/admin/applications/$ID
 *
 * # yes — provisions their restaurant, closed, for them to fill in
 * curl -X POST -H "X-Partner-Admin-Token: $TOKEN" \
 *   https://api.gojogo.app/v1/partner/admin/applications/$ID/approve
 *
 * # no — the note is shown to the applicant, so write it for them
 * curl -X POST -H "X-Partner-Admin-Token: $TOKEN" -H 'Content-Type: application/json' \
 *   -d '{"note":"The licence photo is unreadable — please re-upload it."}' \
 *   https://api.gojogo.app/v1/partner/admin/applications/$ID/reject
 * </pre>
 */
@RestController
@EnableConfigurationProperties(PartnerAdminProperties.class)
class PartnerAdminController {

    static final String TOKEN_HEADER = "X-Partner-Admin-Token";

    private static final Logger log = LoggerFactory.getLogger(PartnerAdminController.class);

    private final PartnerService partners;
    private final PartnerAdminProperties props;

    PartnerAdminController(PartnerService partners, PartnerAdminProperties props) {
        this.partners = partners;
        this.props = props;
        if (props.enabled()) {
            log.info("Partner review endpoints are enabled at /v1/partner/admin/**");
        } else if (props.tooShort()) {
            log.warn("PARTNER_ADMIN_TOKEN is shorter than {} characters, so the partner "
                + "review endpoints stay disabled", PartnerAdminProperties.MIN_TOKEN_LENGTH);
        } else {
            log.warn("PARTNER_ADMIN_TOKEN is unset — nobody can approve a partner "
                + "application, so /v1/delivery has no way to gain a restaurant");
        }
    }

    /** The queue. Defaults to what's actually waiting on a human (SUBMITTED). */
    @GetMapping("/v1/partner/admin/applications")
    List<ReviewApplicationDto> queue(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @RequestParam(required = false) String status,
            @RequestParam(defaultValue = "50") int limit) {
        authorize(token);
        return partners.queue(status, limit);
    }

    /** One application, with a fresh 10-minute signed link per document. */
    @GetMapping("/v1/partner/admin/applications/{accountId}")
    ReviewApplicationDto review(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @PathVariable UUID accountId) {
        authorize(token);
        return partners.review(accountId);
    }

    @PostMapping("/v1/partner/admin/applications/{accountId}/approve")
    ReviewApplicationDto approve(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @PathVariable UUID accountId) {
        authorize(token);
        ReviewApplicationDto reviewed = partners.approve(accountId);
        log.info("Partner {} approved → {} {}", accountId,
            reviewed.account().kind(), reviewed.account().refId());
        return reviewed;
    }

    @PostMapping("/v1/partner/admin/applications/{accountId}/reject")
    ReviewApplicationDto reject(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @PathVariable UUID accountId,
            @Valid @RequestBody RejectDecisionRequest request) {
        authorize(token);
        log.info("Partner {} rejected", accountId);
        return partners.reject(accountId, request.note().trim());
    }

    /** Blocks an approved partner. Their restaurant leaves the catalog; nothing
     *  is deleted, and {@code /approve} puts it back. */
    @PostMapping("/v1/partner/admin/applications/{accountId}/suspend")
    ReviewApplicationDto suspend(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @PathVariable UUID accountId,
            @RequestBody(required = false) ReviewDecisionRequest request) {
        authorize(token);
        String note = request == null || request.note() == null || request.note().isBlank()
            ? "Your restaurant is temporarily suspended." : request.note().trim();
        log.warn("Partner {} suspended", accountId);
        return partners.suspend(accountId, note);
    }

    /** 404 rather than 403: with no token configured — or a wrong one presented
     *  — these paths shouldn't admit that they exist. */
    private void authorize(String presented) {
        if (!props.matches(presented)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such endpoint");
        }
    }
}
