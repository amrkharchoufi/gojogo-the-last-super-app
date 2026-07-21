package com.gojogo.profile;

/**
 * Public API of the profile module. This is the only entry point other
 * modules may use — never the module's repositories or entities.
 */
public interface ProfileApi {

    /**
     * Returns the profile for the given Cognito subject, creating it on first login.
     */
    ProfileDto createOrFetch(String cognitoSub, String email);
}
