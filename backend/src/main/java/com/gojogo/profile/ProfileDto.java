package com.gojogo.profile;

import java.util.UUID;

public record ProfileDto(UUID id, String cognitoSub, String email, String displayName) {
}
