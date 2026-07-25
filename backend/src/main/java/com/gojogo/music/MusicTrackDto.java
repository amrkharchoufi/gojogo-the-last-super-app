package com.gojogo.music;

import java.util.UUID;

/**
 * A catalog track as other modules see it.
 *
 * <p>Consumers are expected to <em>copy</em> these fields onto their own row
 * rather than keep the id alone: a story has to keep playing the sound it was
 * posted with even if the track is later pulled from the catalog or its
 * metadata is corrected.
 *
 * @param audioUrl   the full track; a consumer picks its own clip window out of it
 * @param durationMs the full track's length, so a clip can be bounds-checked
 */
public record MusicTrackDto(
    UUID id,
    String title,
    String artist,
    String artworkUrl,
    String audioUrl,
    int durationMs) {
}
