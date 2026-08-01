/**
 * Auth module — thin layer over Cognito. Owns session establishment (exchanging
 * a valid Cognito JWT for an app-side profile) and, since 2e M5, two
 * operator-facing facts that are read out of Cognito rather than a table:
 * {@link com.gojogo.auth.PlatformAdminApi} — who may work a platform admin
 * surface — and {@link com.gojogo.auth.AccountAdminApi} — disabling and
 * re-enabling sign-in for an account that is being suspended or deleted.
 *
 * <p>Both live here because Cognito lives here. Nothing in {@code auth} knows
 * what a profile, a report or a partner application is: a caller brings a
 * subject and gets an answer.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Auth")
package com.gojogo.auth;
