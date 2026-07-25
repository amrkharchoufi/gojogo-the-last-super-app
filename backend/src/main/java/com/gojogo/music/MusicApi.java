package com.gojogo.music;

import java.util.Optional;
import java.util.UUID;

/**
 * Public API of the music module — the only way another module may touch the
 * catalog.
 *
 * <p>Deliberately narrow, in the same spirit as {@code MessagingApi}: a
 * consumer needs to resolve one track and say that it used it. Browsing and
 * searching stay on the REST surface the client already talks to.
 */
public interface MusicApi {

    /**
     * The track, if it exists and is still active. Empty for a pulled track —
     * callers should reject a <em>new</em> attachment, never retro-break the
     * snapshots already stored against it.
     */
    Optional<MusicTrackDto> find(UUID trackId);

    /**
     * Records that a track was attached to something, which is what feeds the
     * "most used" side of the browse ranking. Best-effort and non-fatal.
     */
    void recordUse(UUID trackId);
}
