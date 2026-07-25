-- Stories · Slice 2, notifications side.
--
-- A story reaction/reply notification points at a frame, not a post, so the
-- activity row needs somewhere to put it — reusing post_id would make the feed
-- try to open a post that doesn't exist.

ALTER TABLE notifications.notification
    ADD COLUMN story_frame_id UUID;
