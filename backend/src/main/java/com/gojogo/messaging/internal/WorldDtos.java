package com.gojogo.messaging.internal;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.util.UUID;

/**
 * Wire DTOs for the My World identity/setup flow (WhatsApp-style: phone-verified
 * private messaging profile with its own display name + avatar).
 */
final class WorldDtos {
    private WorldDtos() {}
}

/** Current caller's World setup state (drives the iOS onboarding gate). */
record WorldProfileDto(boolean setupComplete, String phone, String displayName, String avatarUrl) {
}

record StartPhoneRequest(@NotBlank String phone) {
}

/** True when an SMS was dispatched; the code itself is never returned. */
record StartPhoneResponse(boolean sent) {
}

record VerifyPhoneRequest(@NotBlank String phone, @NotBlank String code) {
}

record UpdateWorldProfileRequest(@Size(max = 60) String displayName, String avatarUrl) {
}

/** A World user discoverable by phone (for starting a conversation). */
record WorldUserDto(UUID profileId, String displayName, String avatarUrl, String phone) {
}
