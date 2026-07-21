/**
 * Auth module — thin layer over Cognito. Owns session establishment:
 * exchanging a valid Cognito JWT for an app-side profile.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Auth")
package com.gojogo.auth;
