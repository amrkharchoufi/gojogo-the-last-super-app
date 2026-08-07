package com.gojogo.social;

import java.util.Collection;
import java.util.Map;
import java.util.UUID;

/**
 * Read-only previews of social content for other modules — the second door out
 * of this module, next to {@link SocialGraphApi}.
 *
 * <p>Batch-shaped on purpose. The caller is the activity feed, which decorates
 * a page of rows at a time; a per-id lookup here would be a query per
 * notification and the N+1 would be invisible until the feed got long.
 *
 * <p>Ids that name nothing (a deleted post, a story frame that expired and was
 * cleaned up) are simply absent from the returned map rather than an error —
 * activity outlives the thing it is about, and a row whose target is gone still
 * has to render.
 */
public interface SocialContentApi {

    /** Thumbnail = the post's first picture; text = its caption. */
    Map<UUID, ContentPreview> postPreviews(Collection<UUID> postIds);

    /** Thumbnail = the frame's picture (a video's poster frame); text = its caption. */
    Map<UUID, ContentPreview> storyFramePreviews(Collection<UUID> frameIds);

    /** Text only — a comment has nothing to show but what it says. */
    Map<UUID, ContentPreview> commentPreviews(Collection<UUID> commentIds);
}
