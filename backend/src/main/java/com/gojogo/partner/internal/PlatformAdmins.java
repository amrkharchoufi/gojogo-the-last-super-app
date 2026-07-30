package com.gojogo.partner.internal;

import org.springframework.http.HttpStatus;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Optional;

/**
 * Decides who is allowed to work the review queue, and — just as importantly —
 * <em>who they are</em>, so a decision about someone's identity documents can
 * be attributed to a person rather than to "whoever had the token".
 */
@Component
class PlatformAdmins {

    /** Cognito puts group membership in the ID token under this claim. */
    private static final String GROUPS_CLAIM = "cognito:groups";

    private final PartnerAdminProperties props;

    PlatformAdmins(PartnerAdminProperties props) {
        this.props = props;
    }

    /**
     * The actor behind this request, or a 404 if there isn't one.
     *
     * <p>404 rather than 403 on purpose: with no operator configured — or a
     * wrong token presented — these paths shouldn't admit that they exist.
     */
    AdminActor require(String presentedToken, Jwt jwt) {
        return resolve(presentedToken, jwt).orElseThrow(
            () -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such endpoint"));
    }

    Optional<AdminActor> resolve(String presentedToken, Jwt jwt) {
        if (isPlatformAdmin(jwt)) {
            // Prefer the person: an email in the audit line beats a subject id.
            String who = jwt.getClaimAsString("email");
            return Optional.of(new AdminActor(who == null ? jwt.getSubject() : who, false));
        }
        if (props.matches(presentedToken)) {
            return Optional.of(new AdminActor("break-glass token", true));
        }
        return Optional.empty();
    }

    /** Whether this caller carries the platform-admin group. Safe with a null
     *  JWT — most callers of these paths have no token at all. */
    boolean isPlatformAdmin(Jwt jwt) {
        if (jwt == null) {
            return false;
        }
        List<String> groups = jwt.getClaimAsStringList(GROUPS_CLAIM);
        return groups != null && groups.contains(props.group());
    }
}

/**
 * Who decided. {@code breakGlass} marks the shared-secret path — worth seeing
 * in a log line, because it is the one that can't name anybody.
 */
record AdminActor(String who, boolean breakGlass) {

    @Override
    public String toString() {
        return breakGlass ? who : "admin " + who;
    }
}
