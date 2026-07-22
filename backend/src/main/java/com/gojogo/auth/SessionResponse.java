package com.gojogo.auth;

import java.util.UUID;

record SessionResponse(UUID profileId, String cognitoSub, String email, String displayName, String handle) {
}
