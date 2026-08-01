package com.gojogo.partner.internal;

import com.gojogo.auth.AdminActor;
import com.gojogo.auth.PlatformAdminApi;
import com.gojogo.profile.ProfileApi;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.UUID;

/**
 * The review queue — and, since Phase 2e M2, the operator's own way to create
 * an application, because every applicant endpoint is scoped to its caller and
 * restaurants are created in the admin tool (2026-07-27). This is the exact
 * surface GoJoAdmin's review console calls; there is no admin-only mirror of
 * the data behind it.
 *
 * <p>Two ways to authenticate, and they are not equal (see
 * {@link PlatformAdminApi}): a real operator signs in with their own Cognito
 * account and carries the {@code platform-admin} group, which makes every
 * decision attributable to a person; the shared {@code PARTNER_ADMIN_TOKEN}
 * stays as break-glass for the operator with no console. Neither is on by
 * default, and a caller with neither gets 404 — these paths don't admit they
 * exist.
 *
 * <p>Nothing here auto-approves and nothing is scheduled: KYC a machine waves
 * through is not KYC.
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
class PartnerAdminController {

    static final String TOKEN_HEADER = "X-Partner-Admin-Token";

    private static final Logger log = LoggerFactory.getLogger(PartnerAdminController.class);

    private final PartnerService partners;
    private final PlatformAdminApi admins;
    private final ProfileApi profiles;
    private final VehicleService vehicles;

    PartnerAdminController(PartnerService partners, PlatformAdminApi admins, ProfileApi profiles,
                           VehicleService vehicles) {
        this.partners = partners;
        this.admins = admins;
        this.profiles = profiles;
        this.vehicles = vehicles;
        log.info("Partner review: members of the '{}' Cognito group can work the queue",
            admins.groupName());
    }

    /** The queue. Defaults to what's actually waiting on a human (SUBMITTED). */
    @GetMapping("/v1/partner/admin/applications")
    List<ReviewApplicationDto> queue(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String kind,
            @RequestParam(defaultValue = "50") int limit) {
        authorize(token, jwt);
        return partners.queue(status, kind, limit);
    }

    /**
     * Creates or edits an application on a merchant's behalf — the gap the
     * applicant endpoints structurally can't fill, since they are all scoped to
     * whoever is calling. Name the owner by profile id or by @handle.
     */
    @PostMapping("/v1/partner/admin/applications")
    @ResponseStatus(HttpStatus.CREATED)
    PartnerAccountDto create(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @Valid @RequestBody AdminCreateApplicationRequest request) {
        AdminActor actor = authorize(token, jwt);
        UUID ownerId = resolveOwner(request);
        PartnerAccountDto saved = partners.adminSave(ownerId, request.application());
        log.info("{} wrote application {} for owner {}", actor, saved.id(), ownerId);
        return saved;
    }

    /** Hands an application the operator filled in to the queue — the same
     *  completeness rules the merchant's own submit runs. */
    @PostMapping("/v1/partner/admin/applications/{accountId}/submit")
    PartnerAccountDto submit(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID accountId) {
        authorize(token, jwt);
        return partners.adminSubmit(accountId);
    }

    /** Somewhere private to put one paper, on the applicant's behalf. The key
     *  lands under <em>their</em> prefix, not the operator's. */
    @PostMapping("/v1/partner/admin/applications/{accountId}/documents/presign")
    DocumentUploadResponse presignDocument(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID accountId,
            @Valid @RequestBody DocumentUploadRequest request) {
        authorize(token, jwt);
        return partners.adminPresignDocument(accountId, request);
    }

    @PutMapping("/v1/partner/admin/applications/{accountId}/documents")
    ReviewApplicationDto attachDocument(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID accountId,
            @Valid @RequestBody AttachDocumentRequest request) {
        authorize(token, jwt);
        return partners.adminAttachDocument(accountId, request);
    }

    @DeleteMapping("/v1/partner/admin/applications/{accountId}/documents/{documentId}")
    ReviewApplicationDto deleteDocument(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID accountId,
            @PathVariable UUID documentId) {
        authorize(token, jwt);
        return partners.adminDeleteDocument(accountId, documentId);
    }

    /**
     * A freshly signed link to one paper. The queue payload already carries
     * links, but they last ten minutes — a console left open on a long review
     * needs to ask again without re-reading the whole application. The bytes
     * never pass through this API: the operator's browser fetches them from S3
     * with a short-lived signature.
     */
    @GetMapping("/v1/partner/admin/applications/{accountId}/documents/{documentId}")
    ReviewDocumentDto document(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID accountId,
            @PathVariable UUID documentId) {
        AdminActor actor = authorize(token, jwt);
        log.info("{} viewed document {} of application {}", actor, documentId, accountId);
        return partners.adminDocument(accountId, documentId);
    }

    /**
     * A vehicle's own papers, freshly signed — the same ten-minute problem as an
     * applicant's ID, on a different object.
     */
    @GetMapping("/v1/partner/admin/vehicles/{vehicleId}/documents/{documentId}")
    ReviewDocumentDto vehicleDocument(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID vehicleId,
            @PathVariable UUID documentId) {
        AdminActor actor = authorize(token, jwt);
        log.info("{} viewed document {} of vehicle {}", actor, documentId, vehicleId);
        return vehicles.document(vehicleId, documentId);
    }

    /**
     * Approves one vehicle, or flags it.
     *
     * <p>Flagging is deliberately not a rejection: the driver re-uploads a
     * certificate and it goes back in the queue. But flagging the car somebody is
     * <em>currently driving</em> suspends the partner in the same breath — a
     * flagged vehicle that keeps receiving work is a flag that did nothing.
     */
    @PostMapping("/v1/partner/admin/applications/{accountId}/vehicles/{vehicleId}/review")
    ReviewApplicationDto reviewVehicle(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID accountId,
            @PathVariable UUID vehicleId,
            @Valid @RequestBody VehicleReviewRequest request) {
        AdminActor actor = authorize(token, jwt);
        log.info("Vehicle {} of application {} {} by {}", vehicleId, accountId,
            request.approved() ? "approved" : "flagged", actor);
        return partners.reviewVehicle(accountId, vehicleId, request.approved(), request.note());
    }

    /** One application, with a fresh 10-minute signed link per document. */
    @GetMapping("/v1/partner/admin/applications/{accountId}")
    ReviewApplicationDto review(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID accountId) {
        authorize(token, jwt);
        return partners.review(accountId);
    }

    @PostMapping("/v1/partner/admin/applications/{accountId}/approve")
    ReviewApplicationDto approve(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID accountId) {
        AdminActor actor = authorize(token, jwt);
        ReviewApplicationDto reviewed = partners.approve(accountId);
        log.info("Partner {} approved by {} → {} {}", accountId, actor,
            reviewed.account().kind(), reviewed.account().refId());
        return reviewed;
    }

    @PostMapping("/v1/partner/admin/applications/{accountId}/reject")
    ReviewApplicationDto reject(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID accountId,
            @Valid @RequestBody RejectDecisionRequest request) {
        AdminActor actor = authorize(token, jwt);
        log.info("Partner {} rejected by {}", accountId, actor);
        return partners.reject(accountId, request.note().trim());
    }

    /** Blocks an approved partner. Their restaurant leaves the catalog; nothing
     *  is deleted, and {@code /approve} puts it back. */
    @PostMapping("/v1/partner/admin/applications/{accountId}/suspend")
    ReviewApplicationDto suspend(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID accountId,
            @RequestBody(required = false) ReviewDecisionRequest request) {
        AdminActor actor = authorize(token, jwt);
        String note = request == null || request.note() == null || request.note().isBlank()
            ? "Your restaurant is temporarily suspended." : request.note().trim();
        log.warn("Partner {} suspended by {}", accountId, actor);
        return partners.suspend(accountId, note);
    }

    /** The operator's own account, or the break-glass token — see
     *  {@link PlatformAdminApi}, which 404s anyone who is neither. */
    private AdminActor authorize(String presented, Jwt jwt) {
        return admins.require(presented, jwt);
    }

    /** By profile id or by @handle: a console has the handle on screen, a
     *  script usually has the id. 404 for someone who doesn't exist rather
     *  than an application filed against a stranger. */
    private UUID resolveOwner(AdminCreateApplicationRequest request) {
        if (request.ownerProfileId() != null) {
            return profiles.findById(request.ownerProfileId())
                .map(p -> p.id())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                    "No such owner profile"));
        }
        String handle = request.ownerHandle() == null ? "" : request.ownerHandle().trim();
        if (handle.startsWith("@")) {
            handle = handle.substring(1);
        }
        if (handle.isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Name the owner with ownerProfileId or ownerHandle");
        }
        return profiles.findByHandle(handle)
            .map(p -> p.id())
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such owner profile"));
    }
}
