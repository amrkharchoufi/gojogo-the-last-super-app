package com.gojogo.profile;

import java.util.Set;
import java.util.UUID;

/**
 * @param kind           PERSON or BUSINESS — see {@link ProfileKind}
 * @param ownerProfileId the person who acts as this profile; null unless BUSINESS
 * @param verified       true only for a KYC-approved business
 */
public record ProfileDto(
    UUID id,
    String cognitoSub,
    String email,
    String displayName,
    String handle,
    String bio,
    String category,
    Integer birthYear,
    String avatarUrl,
    Set<String> interests,
    ProfileKind kind,
    UUID ownerProfileId,
    boolean verified
) {
}
