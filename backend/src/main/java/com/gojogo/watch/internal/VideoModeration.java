package com.gojogo.watch.internal;

import com.gojogo.moderation.ModeratableContent;
import com.gojogo.moderation.ModerationAction;
import com.gojogo.moderation.ModerationTargetKind;
import org.springframework.stereotype.Component;

import java.util.Optional;
import java.util.UUID;

/**
 * Watch's moderation handler — see the {@code moderation} package docs for why
 * this lives here rather than there.
 *
 * <p>Video comments are deliberately not a separate reportable kind. A comment
 * under a video has an owner (the channel) who can delete it themselves, and a
 * moderation queue full of individual comment rows is a queue nobody works; a
 * report against a video is a report against the video.
 */
@Component
class VideoModeration implements ModeratableContent {

    private final VideoService videos;

    VideoModeration(VideoService videos) {
        this.videos = videos;
    }

    @Override
    public ModerationTargetKind kind() {
        return ModerationTargetKind.VIDEO;
    }

    @Override
    public Optional<ModerationTarget> look(UUID targetId) {
        return videos.find(targetId).map(video -> new ModerationTarget(
            video.getAuthorId(),
            video.getDescription() == null || video.getDescription().isBlank()
                ? video.getTitle()
                : video.getTitle() + " — " + video.getDescription(),
            video.isHidden()));
    }

    @Override
    public void apply(UUID targetId, ModerationAction action) {
        switch (action) {
            case HIDE -> videos.setHidden(targetId, true);
            case RESTORE -> videos.setHidden(targetId, false);
            case REMOVE -> videos.removeAsModerator(targetId);
            case SUSPEND -> throw new UnsupportedOperationException("Suspend acts on the account");
        }
    }
}
