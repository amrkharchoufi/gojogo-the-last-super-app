package com.gojogo.profile;

import java.util.UUID;

/**
 * Published when a profile's avatar URL is set to a non-blank value. The media
 * module consumes this to mark the avatar's S3 object as referenced (so the
 * orphan sweep keeps it). An event rather than a direct call because media
 * already depends on profile — a direct profile→media call would be a cycle.
 */
public record ProfileAvatarChanged(UUID profileId, String avatarUrl) {
}
