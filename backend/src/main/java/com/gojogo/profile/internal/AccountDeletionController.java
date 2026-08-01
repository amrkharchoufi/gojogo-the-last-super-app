package com.gojogo.profile.internal;

import com.gojogo.auth.AdminActor;
import com.gojogo.auth.PlatformAdminApi;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Leaving. See {@link AccountDeletionService} for what actually happens and
 * when.
 *
 * <p>{@code DELETE /v1/me} rather than a flag on the profile PATCH, because this
 * is the one request in the app that a user must be able to point at and
 * recognise — and because App Store review looks for exactly this.
 */
@RestController
class AccountDeletionController {

    private final AccountDeletionService deletions;
    private final PlatformAdminApi admins;

    AccountDeletionController(AccountDeletionService deletions, PlatformAdminApi admins) {
        this.deletions = deletions;
        this.admins = admins;
    }

    /**
     * Starts the deletion. Returns 200 with the dates rather than 204: the user
     * has just been told their account will be destroyed, and "when" is the only
     * question they have.
     */
    @DeleteMapping("/v1/me")
    DeletionStatusResponse deleteMe(@AuthenticationPrincipal Jwt jwt) {
        return deletions.request(jwt.getSubject(), jwt.getClaimAsString("email"));
    }

    /**
     * Whether a deletion is pending. Reachable in practice only in the seconds
     * between the request and the token being rejected — kept because a client
     * that retries a failed delete should be able to find out whether it
     * actually took.
     */
    @GetMapping("/v1/me/deletion")
    DeletionStatusResponse status(@AuthenticationPrincipal Jwt jwt) {
        return deletions.statusOf(jwt.getSubject());
    }

    /**
     * An operator undoing a deletion inside its grace period — the support path,
     * on the same admin surface as moderation, because disabling sign-in
     * immediately is what makes a self-service cancel impossible.
     */
    @PostMapping("/v1/moderation/admin/accounts/{profileId}/restore")
    DeletionStatusResponse restore(
            @RequestHeader(name = "X-Partner-Admin-Token", required = false) String token,
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID profileId) {
        AdminActor actor = admins.require(token, jwt);
        return deletions.restore(profileId, actor.toString());
    }
}

/**
 * @param graceEndsAt  when the scrub becomes due — the date the app shows
 * @param anonymizedAt set once it has actually happened, and null before then
 */
record DeletionStatusResponse(boolean pending, OffsetDateTime requestedAt,
                              OffsetDateTime graceEndsAt, OffsetDateTime anonymizedAt) {
}
