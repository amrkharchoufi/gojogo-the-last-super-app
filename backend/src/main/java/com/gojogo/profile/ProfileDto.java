package com.gojogo.profile;

import java.util.Set;
import java.util.UUID;

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
    Set<String> interests
) {
}
