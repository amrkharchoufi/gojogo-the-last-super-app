package com.gojogo.profile;

import java.util.Collection;
import java.util.List;
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

    /**
     * Resolves a batch of handles at once, keyed by the canonical (lowercase)
     * handle. Handles that belong to nobody are simply absent — the caller
     * decides whether that is an error, and for an {@code @tag} in a caption it
     * is not.
     */
    Map<String, ProfileDto> findByHandles(Collection<String> handles);

    /**
     * Prefix search over handle and display name, for pickers — the @-tag
     * autocomplete first. Ordered so handle-prefix matches come before
     * name matches, which is the order a half-typed handle expects.
     */
    List<ProfileDto> search(String query, int limit);

    /** The business-only fields, absent for a person. */
    Optional<BusinessProfileDto> findBusiness(UUID profileId);

    /** The business profiles this person acts as, newest first. */
    List<ProfileDto> businessesOwnedBy(UUID ownerProfileId);

    /**
     * Resolves who a mutation authors as.
     *
     * <p>Returns {@code callerProfileId} when {@code actAsProfileId} is null or
     * is the caller themselves; otherwise the business profile, but only if the
     * caller owns it. Anything else is a 403 — acting as someone is a
     * server-verified ownership check, never a client claim.
     */
    UUID requireActingProfile(UUID callerProfileId, UUID actAsProfileId);

    /**
     * Whether the caller may manage content authored by {@code profileId} —
     * true for their own, and for any business profile they own.
     *
     * <p>The counterpart to {@link #requireActingProfile}: anything you can
     * publish as a business, you must be able to edit and delete as its owner,
     * whichever identity the client happens to be switched to at the time.
     */
    boolean actsFor(UUID callerProfileId, UUID profileId);

    /**
     * Grants or revokes the verified badge on a business. Reserved for a
     * partner approval/suspension — this is the only way a business becomes
     * verified, and the owner-scoped edit surface deliberately has no path to it.
     */
    void setBusinessVerified(UUID businessProfileId, boolean verified);
}
