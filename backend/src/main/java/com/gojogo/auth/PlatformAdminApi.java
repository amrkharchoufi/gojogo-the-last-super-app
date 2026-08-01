package com.gojogo.auth;

import org.springframework.security.oauth2.jwt.Jwt;

import java.util.Optional;

/**
 * Who is allowed to work a platform operator surface, and — just as importantly
 * — <em>who they are</em>, so a decision about somebody's identity documents or
 * somebody's account can be attributed to a person rather than to "whoever had
 * the token".
 *
 * <p>It lives in {@code auth} because the answer is read out of a Cognito claim,
 * and because there must be exactly one of it. Partner review (2b M6) grew its
 * own copy first; moderation (2e M5) needed the same rule, and two definitions
 * of "is this an operator" is one definition away from a surface that stays open
 * after the other one is locked.
 *
 * <p>Two ways in, deliberately unequal:
 * <ul>
 *   <li>a <b>Cognito group</b> (default {@code platform-admin}) carried in the
 *       operator's own ID token — attributable, and what GoJoAdmin signs in
 *       with;</li>
 *   <li>a <b>break-glass token</b> — one shared secret with no identity, for the
 *       operator with no console and for the day Cognito is the broken thing.</li>
 * </ul>
 *
 * <p>Both are off by default: an environment nobody has configured cannot have
 * its partners approved, or its accounts suspended, by a stranger.
 */
public interface PlatformAdminApi {

    /**
     * The actor behind this request, or a 404 if there isn't one.
     *
     * <p>404 rather than 403 on purpose: with no operator configured — or a
     * wrong token presented — these paths shouldn't admit that they exist.
     */
    AdminActor require(String presentedToken, Jwt jwt);

    Optional<AdminActor> resolve(String presentedToken, Jwt jwt);

    /** Whether this caller carries the platform-admin group. Safe with a null
     *  JWT — most callers of these paths have no token at all. */
    boolean isPlatformAdmin(Jwt jwt);

    /** The Cognito group being honoured, for a startup log line. */
    String groupName();
}
