package com.gojogo.social.internal;

import com.gojogo.social.ContentPreview;
import com.gojogo.social.SocialContentApi;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * The {@link SocialContentApi} implementation — previews of posts, story frames
 * and comments for modules that may not read this module's tables.
 *
 * <p>Text is trimmed to a snippet here rather than at the caller. The limit is a
 * property of what a preview <em>is</em> (one line beside a row), not of any one
 * consumer, and a caption can be long enough that shipping it whole to every
 * activity row would be the largest thing in the payload.
 */
@Service
class SocialContentService implements SocialContentApi {

    /** Long enough to recognise the post, short enough to stay one line-ish. */
    private static final int SNIPPET_LIMIT = 140;

    private final PostRepository posts;
    private final StoryFrameRepository frames;
    private final CommentRepository comments;

    SocialContentService(PostRepository posts, StoryFrameRepository frames,
                         CommentRepository comments) {
        this.posts = posts;
        this.frames = frames;
        this.comments = comments;
    }

    @Override
    @Transactional(readOnly = true)
    public Map<UUID, ContentPreview> postPreviews(Collection<UUID> postIds) {
        Set<UUID> ids = distinct(postIds);
        if (ids.isEmpty()) {
            return Map.of();
        }
        Map<UUID, ContentPreview> out = new LinkedHashMap<>();
        for (Post post : posts.withMediaByIds(ids)) {
            out.put(post.getId(), new ContentPreview(post.getId(),
                thumbnailOf(post.getMedia()), snippet(post.getText())));
        }
        return out;
    }

    @Override
    @Transactional(readOnly = true)
    public Map<UUID, ContentPreview> storyFramePreviews(Collection<UUID> frameIds) {
        Set<UUID> ids = distinct(frameIds);
        if (ids.isEmpty()) {
            return Map.of();
        }
        Map<UUID, ContentPreview> out = new LinkedHashMap<>();
        // Expired frames are deliberately included: a story lives 24 hours but
        // the "reacted to your story" row it produced outlives it, and a row
        // with no picture reads as a bug rather than as yesterday.
        for (StoryFrame frame : frames.findLiveByIds(ids)) {
            out.put(frame.getId(), new ContentPreview(frame.getId(),
                frame.getImageUrl(), snippet(frame.getCaption())));
        }
        return out;
    }

    @Override
    @Transactional(readOnly = true)
    public Map<UUID, ContentPreview> commentPreviews(Collection<UUID> commentIds) {
        Set<UUID> ids = distinct(commentIds);
        if (ids.isEmpty()) {
            return Map.of();
        }
        Map<UUID, ContentPreview> out = new LinkedHashMap<>();
        for (Comment comment : comments.findAllById(ids)) {
            out.put(comment.getId(),
                new ContentPreview(comment.getId(), null, snippet(comment.getText())));
        }
        return out;
    }

    /** The first slide that actually has a picture — a video's poster counts. */
    private static String thumbnailOf(List<PostMedia> media) {
        return media.stream()
            .map(PostMedia::getImageUrl)
            .filter(url -> url != null && !url.isBlank())
            .findFirst()
            .orElse(null);
    }

    private static String snippet(String text) {
        if (text == null) {
            return null;
        }
        String cleaned = text.strip().replaceAll("\\s+", " ");
        if (cleaned.isEmpty()) {
            return null;
        }
        return cleaned.length() <= SNIPPET_LIMIT
            ? cleaned
            : cleaned.substring(0, SNIPPET_LIMIT).stripTrailing() + "…";
    }

    private static Set<UUID> distinct(Collection<UUID> ids) {
        if (ids == null || ids.isEmpty()) {
            return Set.of();
        }
        Set<UUID> out = new LinkedHashSet<>(ids);
        out.remove(null);
        return out;
    }
}
