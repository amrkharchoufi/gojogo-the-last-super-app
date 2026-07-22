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
        return posts.create(current.require(jwt).id(), request);
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
    void like(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID postId) {
        posts.like(current.require(jwt).id(), postId);
    }

    @DeleteMapping("/v1/posts/{postId}/like")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void unlike(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID postId) {
        posts.unlike(current.require(jwt).id(), postId);
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

    @GetMapping("/v1/posts/{postId}/comments")
    List<CommentResponse> forPost(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID postId) {
        return comments.forPost(current.require(jwt).id(), postId);
    }

    @PostMapping("/v1/posts/{postId}/comments")
    @ResponseStatus(HttpStatus.CREATED)
    CommentResponse create(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID postId,
                           @Valid @RequestBody CreateCommentRequest request) {
        return comments.create(current.require(jwt).id(), postId, request.text());
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
    void follow(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID profileId) {
        follows.follow(current.require(jwt).id(), profileId);
    }

    @DeleteMapping("/v1/profiles/{profileId}/follow")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void unfollow(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID profileId) {
        follows.unfollow(current.require(jwt).id(), profileId);
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
        return stories.create(current.require(jwt).id(), request.frameImageUrls());
    }

    @PostMapping("/v1/stories/frames/{frameId}/seen")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void markSeen(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID frameId) {
        stories.markSeen(current.require(jwt).id(), frameId);
    }
}
