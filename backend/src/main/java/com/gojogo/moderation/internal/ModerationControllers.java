package com.gojogo.moderation.internal;

import com.gojogo.auth.AdminActor;
import com.gojogo.auth.PlatformAdminApi;
import com.gojogo.profile.ProfileApi;
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
 * Reporting, from the app.
 *
 * <p>One endpoint, and it tells the reporter almost nothing back — what happens
 * to a report is not the reporter's business, and a product that says "we
 * removed it" invites people to report things to find out whether they can.
 */
@RestController
class ReportController {

    private final ModerationService moderation;
    private final ProfileApi profiles;

    ReportController(ModerationService moderation, ProfileApi profiles) {
        this.moderation = moderation;
        this.profiles = profiles;
    }

    @PostMapping("/v1/reports")
    @ResponseStatus(HttpStatus.CREATED)
    ReportReceipt report(@AuthenticationPrincipal Jwt jwt,
                         @Valid @RequestBody CreateReportRequest request) {
        UUID me = profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email")).id();
        return moderation.report(me, request.targetKind(), request.targetId(),
            request.reason(), request.note());
    }

    /** The picker's contents, so the app never hardcodes a list the server
     *  might grow. Public to any signed-in caller; there is nothing in it. */
    @GetMapping("/v1/reports/reasons")
    List<String> reasons() {
        return java.util.Arrays.stream(ReportReason.values()).map(Enum::name).toList();
    }
}

/**
 * The queue a human works — the surface GoJoAdmin's moderation console will
 * call, on the same terms as partner review (2e M2): the operator's own Cognito
 * account carrying the {@code platform-admin} group, or the break-glass
 * {@code PARTNER_ADMIN_TOKEN}. A caller with neither gets 404; these paths do
 * not admit that they exist.
 *
 * <p>Nothing here is scheduled and nothing is automatic. A takedown is a
 * person's decision, for the same reason a KYC approval is.
 *
 * <pre>
 * # what's waiting
 * curl -H "X-Partner-Admin-Token: $TOKEN" \
 *   https://api.gojogo.app/v1/moderation/admin/reports
 *
 * # hide it — reversible, and its author still sees it
 * curl -X POST -H "X-Partner-Admin-Token: $TOKEN" -H 'Content-Type: application/json' \
 *   -d '{"action":"HIDE","note":"Nudity, first offence"}' \
 *   https://api.gojogo.app/v1/moderation/admin/reports/$ID/action
 *
 * # nothing wrong here
 * curl -X POST -H "X-Partner-Admin-Token: $TOKEN" -H 'Content-Type: application/json' \
 *   -d '{"note":"Disagreement, not abuse"}' \
 *   https://api.gojogo.app/v1/moderation/admin/reports/$ID/dismiss
 * </pre>
 */
@RestController
class ModerationAdminController {

    static final String TOKEN_HEADER = "X-Partner-Admin-Token";

    private final ModerationService moderation;
    private final PlatformAdminApi admins;

    ModerationAdminController(ModerationService moderation, PlatformAdminApi admins) {
        this.moderation = moderation;
        this.admins = admins;
    }

    @GetMapping("/v1/moderation/admin/reports")
    List<ReviewReportDto> queue(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String kind,
            @RequestParam(defaultValue = "50") int limit) {
        admins.require(token, jwt);
        return moderation.queue(status, kind, limit);
    }

    @GetMapping("/v1/moderation/admin/reports/summary")
    QueueSummary summary(@RequestHeader(name = TOKEN_HEADER, required = false) String token,
                         @AuthenticationPrincipal Jwt jwt) {
        admins.require(token, jwt);
        return moderation.summary();
    }

    @GetMapping("/v1/moderation/admin/reports/{reportId}")
    ReviewReportDto one(@RequestHeader(name = TOKEN_HEADER, required = false) String token,
                        @AuthenticationPrincipal Jwt jwt,
                        @PathVariable UUID reportId) {
        admins.require(token, jwt);
        return moderation.get(reportId);
    }

    /** Everything ever filed against one account — the context a suspension is
     *  decided in, rather than the single report in front of you. */
    @GetMapping("/v1/moderation/admin/accounts/{profileId}/reports")
    List<ReviewReportDto> history(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID profileId,
            @RequestParam(defaultValue = "50") int limit) {
        admins.require(token, jwt);
        return moderation.history(profileId, limit);
    }

    @PostMapping("/v1/moderation/admin/reports/{reportId}/action")
    ReviewReportDto act(@RequestHeader(name = TOKEN_HEADER, required = false) String token,
                        @AuthenticationPrincipal Jwt jwt,
                        @PathVariable UUID reportId,
                        @Valid @RequestBody ModerationDecisionRequest request) {
        AdminActor actor = admins.require(token, jwt);
        return moderation.act(reportId, request.action(), request.note(), actor.toString());
    }

    @PostMapping("/v1/moderation/admin/reports/{reportId}/dismiss")
    ReviewReportDto dismiss(@RequestHeader(name = TOKEN_HEADER, required = false) String token,
                            @AuthenticationPrincipal Jwt jwt,
                            @PathVariable UUID reportId,
                            @RequestBody(required = false) DismissRequest request) {
        AdminActor actor = admins.require(token, jwt);
        return moderation.dismiss(reportId, request == null ? null : request.note(),
            actor.toString());
    }
}
