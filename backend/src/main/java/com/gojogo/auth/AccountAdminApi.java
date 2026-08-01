package com.gojogo.auth;

/**
 * Turning an account's ability to sign in off and on again.
 *
 * <p>Two callers, and they want the same thing for opposite reasons:
 * {@code moderation} suspends somebody, and {@code profile} starts the deletion
 * clock. Both need Cognito to stop issuing tokens; neither should have to know
 * that Cognito is what's behind it, which is why this is an interface in
 * {@code auth} rather than a Cognito client passed around.
 *
 * <p><b>Disabling is not deleting.</b> The Cognito user survives, so a
 * suspension can be lifted and a deletion can be undone during its grace period.
 * The account's data is untouched by anything here — this only closes the door.
 *
 * <p><b>Unconfigured is a mode, not a failure</b> (the posture payments and kyc
 * already take): with no user pool configured — a test boot, a local run — the
 * call logs and returns {@code false} rather than throwing, so the platform-side
 * record of a suspension or a deletion request is still written. What it must
 * never do is claim success it didn't have, which is what the boolean is for.
 */
public interface AccountAdminApi {

    /**
     * Stops this Cognito subject from signing in, and revokes the refresh tokens
     * that would otherwise keep an existing session alive for weeks.
     *
     * @return whether Cognito actually acknowledged it
     */
    boolean disableSignIn(String cognitoSub);

    /** Lets them back in — lifting a suspension, or cancelling a deletion. */
    boolean enableSignIn(String cognitoSub);
}
