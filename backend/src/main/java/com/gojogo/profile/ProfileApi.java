package com.gojogo.profile;

import java.util.Collection;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * Public API of the profile module. This is the only entry point other
 * modules may use — never the module's repositories or entities.
 */
public interface ProfileApi {

    /**
     * Returns the profile for the given Cognito subject, creating it on first login.
     */
    ProfileDto createOrFetch(String cognitoSub, String email);

    Optional<ProfileDto> findById(UUID id);

    Optional<ProfileDto> findByHandle(String handle);

    /**
     * Batch lookup for decorating content with author info. Missing ids are absent from the map.
     */
    Map<UUID, ProfileDto> findByIds(Collection<UUID> ids);
}
