package com.gojogo.social.internal;

import com.gojogo.moderation.ModeratableContent;
import com.gojogo.moderation.ModerationAction;
import com.gojogo.moderation.ModerationTargetKind;
import com.gojogo.profile.ProfileApi;
import org.springframework.stereotype.Component;

import java.util.Optional;
import java.util.UUID;

/**
 * Social's four moderation handlers — posts, comments, stories and profiles.
 *
 * <p>They live here rather than in {@code moderation} because only this module
 * can answer what a post is and whose it is. The dependency runs vertical →
 * platform (see the moderation package docs), and it is one-way: nothing in
 * {@code social}'s own surfaces knows these classes exist.
 *
 * <p>The summary each returns is deliberately the content's own words rather
 * than a description: a moderator deciding about a caption should read the
 * caption.
 */
@Component
class PostModeration implements ModeratableContent {

    private final PostService posts;

    PostModeration(PostService posts) {
        this.posts = posts;
    }

    @Override
    public ModerationTargetKind kind() {
        return ModerationTargetKind.POST;
    }

    @Override
    public Optional<ModerationTarget> look(UUID targetId) {
        return posts.find(targetId).map(post -> new ModerationTarget(
            post.getAuthorId(),
            post.getText() == null || post.getText().isBlank()
                // A photo with no caption is the common case, and "(no caption)"
                // is more useful to a moderator than an empty line.
                ? "(" + post.getMedia().size() + " photo/video, no caption)"
                : post.getText(),
            post.isHidden()));
    }

    @Override
    public void apply(UUID targetId, ModerationAction action) {
        switch (action) {
            case HIDE -> posts.setHidden(targetId, true);
            case RESTORE -> posts.setHidden(targetId, false);
            case REMOVE -> posts.removeAsModerator(targetId);
            case SUSPEND -> throw new UnsupportedOperationException("Suspend acts on the account");
        }
    }
}

@Component
class CommentModeration implements ModeratableContent {

    private final CommentService comments;

    CommentModeration(CommentService comments) {
        this.comments = comments;
    }

    @Override
    public ModerationTargetKind kind() {
        return ModerationTargetKind.COMMENT;
    }

    @Override
    public Optional<ModerationTarget> look(UUID targetId) {
        return comments.find(targetId).map(c ->
            new ModerationTarget(c.getAuthorId(), c.getText(), c.isHidden()));
    }

    @Override
    public void apply(UUID targetId, ModerationAction action) {
        switch (action) {
            case HIDE -> comments.setHidden(targetId, true);
            case RESTORE -> comments.setHidden(targetId, false);
            case REMOVE -> comments.removeAsModerator(targetId);
            case SUSPEND -> throw new UnsupportedOperationException("Suspend acts on the account");
        }
    }
}

@Component
class StoryModeration implements ModeratableContent {

    private final StoryService stories;

    StoryModeration(StoryService stories) {
        this.stories = stories;
    }

    @Override
    public ModerationTargetKind kind() {
        return ModerationTargetKind.STORY;
    }

    @Override
    public Optional<ModerationTarget> look(UUID targetId) {
        return stories.findFrame(targetId).map(frame -> new ModerationTarget(
            frame.getAuthorId(),
            frame.getCaption() == null || frame.getCaption().isBlank()
                ? "(" + frame.getMediaType() + " story, no caption)"
                : frame.getCaption(),
            frame.isHidden()));
    }

    @Override
    public void apply(UUID targetId, ModerationAction action) {
        switch (action) {
            case HIDE -> stories.setHidden(targetId, true);
            case RESTORE -> stories.setHidden(targetId, false);
            case REMOVE -> stories.removeAsModerator(targetId);
            case SUSPEND -> throw new UnsupportedOperationException("Suspend acts on the account");
        }
    }
}

/**
 * The account itself, for behaviour no single post captures — a handle that
 * impersonates someone, a bio full of a phone number, a pattern across content
 * that is individually fine.
 *
 * <p><b>Only two of the four verbs mean anything here</b>, and the other two say
 * so rather than quietly doing nothing. There is no "hidden profile": making an
 * account invisible to everyone but itself is a shadowban, which is a product
 * decision this milestone is not making. Deleting a profile is
 * {@code DELETE /v1/me}'s job and is the account holder's own right, not a
 * moderator's shortcut. What is left is {@code SUSPEND} — handled by the
 * moderation module, since it is Cognito rather than a profile row — so this
 * handler exists mainly to make a profile <em>reportable</em> and to name whose
 * it is.
 */
@Component
class ProfileModeration implements ModeratableContent {

    private final ProfileApi profiles;

    ProfileModeration(ProfileApi profiles) {
        this.profiles = profiles;
    }

    @Override
    public ModerationTargetKind kind() {
        return ModerationTargetKind.PROFILE;
    }

    @Override
    public Optional<ModerationTarget> look(UUID targetId) {
        return profiles.findById(targetId).map(p -> new ModerationTarget(
            // The owner of a profile is the profile: a suspension decision reads
            // this, and the module refuses a business by name rather than
            // reaching through to the person behind it.
            p.id(),
            "@" + p.handle() + (p.displayName() == null ? "" : " — " + p.displayName())
                + (p.bio() == null || p.bio().isBlank() ? "" : " · " + p.bio()),
            false));
    }

    @Override
    public void apply(UUID targetId, ModerationAction action) {
        throw new UnsupportedOperationException(
            "An account can only be suspended or reinstated, not " + action.name().toLowerCase()
                + "n — hiding an account is a shadowban, and deleting one is its owner's right");
    }
}
