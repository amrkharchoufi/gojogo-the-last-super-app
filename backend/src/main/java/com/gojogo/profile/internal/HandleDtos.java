package com.gojogo.profile.internal;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;

/** Request body for the dedicated username-change endpoint. */
record ChangeHandleRequest(
    @NotBlank @Size(min = 2, max = 30) @Pattern(regexp = "[A-Za-z0-9_.]+") String handle) {
}

/**
 * Availability check result. {@code reason}: "ok" | "taken" | "invalid" |
 * "current" (the caller's own handle). {@code normalized} is the lowercased,
 * sanitized form the server would actually store.
 */
record HandleAvailabilityResponse(boolean available, String reason, String normalized) {
}

/**
 * Cooldown state for the caller's own handle so the UI can gate the change
 * control. {@code changeAvailableAt} is null when a change is allowed now.
 */
record HandleStatusResponse(String handle, OffsetDateTime handleChangedAt,
                            OffsetDateTime changeAvailableAt, boolean canChangeNow) {
}

/**
 * One row of the people picker. Deliberately narrower than {@link
 * com.gojogo.profile.ProfileDto}: an autocomplete needs a face, a name and a
 * handle, and must not hand out the email or Cognito subject of everyone whose
 * username starts with the same two letters.
 */
record ProfileSearchResult(java.util.UUID id, String name, String handle, String avatarUrl,
                           boolean business, boolean verified) {
}
