package com.gojogo.profile.internal;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.util.Set;

/**
 * PATCH semantics: null field = leave unchanged; blank avatarUrl clears it.
 */
record UpdateProfileRequest(
    @Size(max = 120) String displayName,
    @Size(min = 2, max = 30) @Pattern(regexp = "[A-Za-z0-9_.]+") String handle,
    @Size(max = 2000) String bio,
    @Size(max = 60) String category,
    @Min(1900) @Max(2100) Integer birthYear,
    @Size(max = 500) String avatarUrl,
    Set<@Size(max = 60) String> interests
) {
}
