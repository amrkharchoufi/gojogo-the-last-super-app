package com.gojogo.social.internal;

import jakarta.validation.Valid;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

@RestController
class PostController {

    private final PostService posts;
    private final CurrentProfiles current;

    PostController(PostService posts, CurrentProfiles current) {
        this.posts = posts;
        this.current = current;
    }

    @GetMapping("/v1/feed")
    FeedResponse feed(@AuthenticationPrincipal Jwt jwt,
                      @RequestParam(required = false)
                      @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) OffsetDateTime before,
                      @RequestParam(defaultValue = "20") int limit) {
        return posts.feed(current.require(jwt).id(), before, limit);
    }

    @PostMapping("/v1/posts")
    @ResponseStatus(HttpStatus.CREATED)
    PostResponse create(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody CreatePostRequest request) {
        return posts.create(current.actingId(jwt, request.actAsProfileId()), request);
    }

    @GetMapping("/v1/posts/{postId}")
    PostResponse get(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID postId) {
        return posts.get(current.require(jwt).id(), postId);
    }

    @DeleteMapping("/v1/posts/{postId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void delete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID postId) {
        posts.delete(current.require(jwt).id(), postId);
    }

    @PostMapping("/v1/posts/{postId}/like")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void like(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID postId,
              @RequestParam(required = false) UUID actAs) {
        posts.like(current.actingId(jwt, actAs), postId);
    }

    @DeleteMapping("/v1/posts/{postId}/like")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void unlike(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID postId,
                @RequestParam(required = false) UUID actAs) {
        posts.unlike(current.actingId(jwt, actAs), postId);
    }

    @PostMapping("/v1/posts/{postId}/bookmark")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void bookmark(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID postId) {
        posts.bookmark(current.require(jwt).id(), postId);
    }

    @DeleteMapping("/v1/posts/{postId}/bookmark")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void unbookmark(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID postId) {
        posts.unbookmark(current.require(jwt).id(), postId);
    }
}

@RestController
class CommentController {

    private final CommentService comments;
    private final CurrentProfiles current;

    CommentController(CommentService comments, CurrentProfiles current) {
        this.comments = comments;
        this.current = current;
    }

    /** The whole thread — top-level comments, each with its replies nested. */
    @GetMapping("/v1/posts/{postId}/comments")
    List<CommentResponse> forPost(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID postId) {
        return comments.forPost(current.require(jwt).id(), postId);
    }

    /** Posts a comment, or a reply to one when the body carries a {@code parentId}. */
    @PostMapping("/v1/posts/{postId}/comments")
    @ResponseStatus(HttpStatus.CREATED)
    CommentResponse create(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID postId,
                           @Valid @RequestBody CreateCommentRequest request) {
        return comments.create(current.actingId(jwt, request.actAsProfileId()), postId,
            request.text(), request.parentId());
    }

    /** One comment's replies on their own, for a thread the feed only previewed. */
    @GetMapping("/v1/comments/{commentId}/replies")
    List<CommentResponse> replies(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID commentId) {
        return comments.replies(current.require(jwt).id(), commentId);
    }

    @PostMapping("/v1/comments/{commentId}/like")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void like(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID commentId) {
        comments.like(current.require(jwt).id(), commentId);
    }

    @DeleteMapping("/v1/comments/{commentId}/like")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void unlike(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID commentId) {
        comments.unlike(current.require(jwt).id(), commentId);
    }
}

@RestController
class FollowController {

    private final FollowService follows;
    private final PostService posts;
    private final CurrentProfiles current;

    FollowController(FollowService follows, PostService posts, CurrentProfiles current) {
        this.follows = follows;
        this.posts = posts;
        this.current = current;
    }

    @GetMapping("/v1/profiles/{profileId}")
    ProfileViewResponse view(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID profileId) {
        return follows.view(current.require(jwt).id(), profileId);
    }

    @GetMapping("/v1/profiles/by-handle/{handle}")
    ProfileViewResponse viewByHandle(@AuthenticationPrincipal Jwt jwt, @PathVariable String handle) {
        return follows.viewByHandle(current.require(jwt).id(), handle);
    }

    @GetMapping("/v1/profiles/{profileId}/posts")
    List<PostResponse> profilePosts(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID profileId,
                                    @RequestParam(defaultValue = "30") int limit) {
        return posts.byAuthor(current.require(jwt).id(), profileId, limit);
    }

    @PostMapping("/v1/profiles/{profileId}/follow")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void follow(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID profileId,
                @RequestParam(required = false) UUID actAs) {
        follows.follow(current.actingId(jwt, actAs), profileId);
    }

    @DeleteMapping("/v1/profiles/{profileId}/follow")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void unfollow(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID profileId,
                  @RequestParam(required = false) UUID actAs) {
        follows.unfollow(current.actingId(jwt, actAs), profileId);
    }
}

/**
 * Blocking (SPECS §10). Separate from {@link FollowController} because it is the
 * opposite kind of relationship and reads as one in the routing table, not
 * because the two don't touch — a block unfollows, in the same transaction.
 *
 * <p>There is deliberately no way to ask "who blocked me": the list is your own
 * blocks, which are the only ones you can undo.
 */
@RestController
class BlockController {

    private final BlockService blocks;
    private final CurrentProfiles current;

    BlockController(BlockService blocks, CurrentProfiles current) {
        this.blocks = blocks;
        this.current = current;
    }

    @GetMapping("/v1/me/blocks")
    List<BlockedProfileDto> mine(@AuthenticationPrincipal Jwt jwt) {
        return blocks.mine(current.require(jwt).id());
    }

    @PostMapping("/v1/profiles/{profileId}/block")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void block(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID profileId) {
        blocks.block(current.require(jwt).id(), profileId);
    }

    @DeleteMapping("/v1/profiles/{profileId}/block")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void unblock(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID profileId) {
        blocks.unblock(current.require(jwt).id(), profileId);
    }
}

@RestController
class StoryController {

    private final StoryService stories;
    private final CurrentProfiles current;

    StoryController(StoryService stories, CurrentProfiles current) {
        this.stories = stories;
        this.current = current;
    }

    @GetMapping("/v1/stories")
    List<StoryRingResponse> rings(@AuthenticationPrincipal Jwt jwt) {
        return stories.rings(current.require(jwt).id());
    }

    @PostMapping("/v1/stories")
    @ResponseStatus(HttpStatus.CREATED)
    List<StoryFrameDto> create(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody CreateStoryRequest request) {
        return stories.create(current.actingId(jwt, request.actAsProfileId()), request);
    }

    @PostMapping("/v1/stories/frames/{frameId}/seen")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void markSeen(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID frameId) {
        stories.markSeen(current.require(jwt).id(), frameId);
    }

    @DeleteMapping("/v1/stories/frames/{frameId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void delete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID frameId) {
        stories.delete(current.require(jwt).id(), frameId);
    }
}

/** Reactions, replies, the viewers list and muting — see StoryEngagementService. */
@RestController
class StoryEngagementController {

    private final StoryEngagementService engagement;
    private final CurrentProfiles current;

    StoryEngagementController(StoryEngagementService engagement, CurrentProfiles current) {
        this.engagement = engagement;
        this.current = current;
    }

    @PutMapping("/v1/stories/frames/{frameId}/reaction")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void react(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID frameId,
               @Valid @RequestBody StoryReactionRequest request) {
        engagement.react(current.require(jwt).id(), frameId, request.emoji());
    }

    @DeleteMapping("/v1/stories/frames/{frameId}/reaction")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void unreact(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID frameId) {
        engagement.unreact(current.require(jwt).id(), frameId);
    }

    @GetMapping("/v1/stories/frames/{frameId}/replies")
    List<StoryCommentDto> replies(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID frameId) {
        return engagement.replies(current.require(jwt).id(), frameId);
    }

    @PostMapping("/v1/stories/frames/{frameId}/replies")
    @ResponseStatus(HttpStatus.CREATED)
    StoryCommentDto reply(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID frameId,
                          @Valid @RequestBody StoryReplyRequest request) {
        return engagement.reply(current.require(jwt).id(), frameId, request.text());
    }

    @DeleteMapping("/v1/stories/replies/{replyId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void deleteReply(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID replyId) {
        engagement.deleteReply(current.require(jwt).id(), replyId);
    }

    @GetMapping("/v1/stories/frames/{frameId}/viewers")
    List<StoryViewerDto> viewers(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID frameId) {
        return engagement.viewers(current.require(jwt).id(), frameId);
    }

    @PostMapping("/v1/stories/mute/{profileId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void mute(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID profileId) {
        engagement.mute(current.require(jwt).id(), profileId);
    }

    @DeleteMapping("/v1/stories/mute/{profileId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void unmute(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID profileId) {
        engagement.unmute(current.require(jwt).id(), profileId);
    }
}

/** The archive, profile highlights and the close-friends list. */
@RestController
class StoryHighlightController {

    private final StoryHighlightService highlights;
    private final CurrentProfiles current;

    StoryHighlightController(StoryHighlightService highlights, CurrentProfiles current) {
        this.highlights = highlights;
        this.current = current;
    }

    /** Your archive, or one of your business profiles' ({@code asProfileId}). */
    @GetMapping("/v1/stories/archive")
    List<StoryFrameDto> archive(@AuthenticationPrincipal Jwt jwt,
                                @RequestParam(required = false) UUID asProfileId) {
        return highlights.archive(current.actingId(jwt, asProfileId));
    }

    /** Someone else's highlights when {@code profileId} is given, yours otherwise. */
    @GetMapping("/v1/stories/highlights")
    List<StoryHighlightDto> list(@AuthenticationPrincipal Jwt jwt,
                                 @RequestParam(required = false) UUID profileId) {
        UUID me = current.require(jwt).id();
        return highlights.highlightsOf(profileId == null ? me : profileId);
    }

    @GetMapping("/v1/stories/highlights/{highlightId}")
    StoryHighlightDetailDto get(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID highlightId) {
        return highlights.highlight(current.require(jwt).id(), highlightId);
    }

    @PostMapping("/v1/stories/highlights")
    @ResponseStatus(HttpStatus.CREATED)
    StoryHighlightDto create(@AuthenticationPrincipal Jwt jwt,
                             @Valid @RequestBody SaveHighlightRequest request) {
        return highlights.create(current.actingId(jwt, request.actAsProfileId()), request);
    }

    @PutMapping("/v1/stories/highlights/{highlightId}")
    StoryHighlightDto update(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID highlightId,
                             @Valid @RequestBody SaveHighlightRequest request) {
        return highlights.update(current.require(jwt).id(), highlightId, request);
    }

    @DeleteMapping("/v1/stories/highlights/{highlightId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void delete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID highlightId) {
        highlights.delete(current.require(jwt).id(), highlightId);
    }

    @GetMapping("/v1/stories/close-friends")
    List<CloseFriendDto> closeFriends(@AuthenticationPrincipal Jwt jwt,
                                      @RequestParam(required = false) UUID asProfileId) {
        return highlights.closeFriendsOf(current.actingId(jwt, asProfileId));
    }

    /** A business keeps its own close-friends audience: the list belongs to
     *  whichever identity posts the story, not to the person behind it. */
    @PutMapping("/v1/stories/close-friends")
    List<CloseFriendDto> setCloseFriends(@AuthenticationPrincipal Jwt jwt,
                                         @Valid @RequestBody CloseFriendsRequest request) {
        return highlights.setCloseFriends(current.actingId(jwt, request.actAsProfileId()),
            request.profileIds());
    }
}
