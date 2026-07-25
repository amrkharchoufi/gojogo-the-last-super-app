-- Placeholder music so the story music picker can be exercised end to end.
--
-- These four tracks are SYNTHESISED — generated from sine/saw math, with no
-- source recording, sample pack or third-party audio anywhere in them, so there
-- is nothing to license. They exist to prove the picker, the clip scrubber, the
-- waveform, the sticker and video/music mixing all work. They are not meant to
-- be what users actually hear.
--
-- TO REMOVE, once you have a real catalog:
--     UPDATE music.track SET is_active = false WHERE artist = 'GojoGo Sound';
--   or, to drop them outright (safe — no FK points here; a story that used one
--   keeps its own snapshot and goes on playing):
--     DELETE FROM music.track WHERE artist = 'GojoGo Sound';
--
-- durations are the real encoded lengths (afinfo), which matters: the clip
-- window is clamped against duration_ms, so a wrong value here would let a
-- clip run off the end of the audio.

INSERT INTO music.track (title, artist, artwork_url, audio_url, duration_ms, trending_rank)
SELECT * FROM (VALUES
    ('Night Drive',     'GojoGo Sound',
     'https://gojogo-user-media-578109959809.s3.amazonaws.com/media/music/night-drive.jpg',
     'https://gojogo-user-media-578109959809.s3.amazonaws.com/media/music/night-drive.m4a',
     35285, 1),
    ('Casablanca Blue', 'GojoGo Sound',
     'https://gojogo-user-media-578109959809.s3.amazonaws.com/media/music/casablanca-blue.jpg',
     'https://gojogo-user-media-578109959809.s3.amazonaws.com/media/music/casablanca-blue.m4a',
     39181, 2),
    ('Atlas Morning',   'GojoGo Sound',
     'https://gojogo-user-media-578109959809.s3.amazonaws.com/media/music/atlas-morning.jpg',
     'https://gojogo-user-media-578109959809.s3.amazonaws.com/media/music/atlas-morning.m4a',
     41000, 3),
    ('Medina Late',     'GojoGo Sound',
     'https://gojogo-user-media-578109959809.s3.amazonaws.com/media/music/medina-late.jpg',
     'https://gojogo-user-media-578109959809.s3.amazonaws.com/media/music/medina-late.m4a',
     34750, 4)
) AS seed(title, artist, artwork_url, audio_url, duration_ms, trending_rank)
-- Guarded so a repair/re-run can't double the catalog.
WHERE NOT EXISTS (SELECT 1 FROM music.track t WHERE t.audio_url = seed.audio_url);
