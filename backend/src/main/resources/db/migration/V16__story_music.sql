-- Sound on a story frame.
--
-- The track's metadata is COPIED here, not referenced by id alone (and there is
-- deliberately no FK — `music` and `social` are different schemas, and §4 of
-- ARCHITECTURE.md forbids crossing them). A story has to keep playing the sound
-- it was posted with even after the track is pulled from the catalog or its
-- title is corrected, and rendering the music sticker must not need a
-- cross-module read. Same reasoning as messaging's ConversationContext.

ALTER TABLE social.story_frame
    ADD COLUMN music_track_id     UUID,
    ADD COLUMN music_title        TEXT,
    ADD COLUMN music_artist       TEXT,
    ADD COLUMN music_artwork_url  TEXT,
    ADD COLUMN music_audio_url    TEXT,
    -- The clip window chosen in the composer, within the full track.
    ADD COLUMN music_start_ms     INT,
    ADD COLUMN music_duration_ms  INT;

ALTER TABLE social.story_frame
    -- Either the frame has a whole sound or none of one; a half-populated
    -- snapshot would render a sticker with nothing to play.
    ADD CONSTRAINT story_frame_music_chk CHECK (
        music_track_id IS NULL
        OR (music_audio_url IS NOT NULL
            AND music_title IS NOT NULL
            AND music_start_ms IS NOT NULL
            AND music_duration_ms IS NOT NULL)
    );
