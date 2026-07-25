package com.gojogo.watch.internal;

import jakarta.validation.Valid;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
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
class VideoController {

    private final VideoService videos;
    private final WatchCurrentProfile current;

    VideoController(VideoService videos, WatchCurrentProfile current) {
        this.videos = videos;
        this.current = current;
    }

    /** The Watch feed. {@code kind=SHORT} serves the vertical Shorts pager. */
    @GetMapping("/v1/videos")
    VideoFeedResponse feed(@AuthenticationPrincipal Jwt jwt,
                           @RequestParam(defaultValue = "LONG_FORM") String kind,
                           @RequestParam(defaultValue = "20") int limit,
                           @RequestParam(required = false)
                           @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) OffsetDateTime before) {
        return videos.feed(current.require(jwt).id(), kind, limit, before);
    }

    @GetMapping("/v1/videos/saved")
    List<VideoResponse> saved(@AuthenticationPrincipal Jwt jwt,
                              @RequestParam(defaultValue = "50") int limit) {
        return videos.saved(current.require(jwt).id(), limit);
    }

    @PostMapping("/v1/videos")
    @ResponseStatus(HttpStatus.CREATED)
    VideoResponse create(@AuthenticationPrincipal Jwt jwt,
                         @Valid @RequestBody CreateVideoRequest request) {
        return videos.create(current.require(jwt).id(), request);
    }

    @GetMapping("/v1/videos/{videoId}")
    VideoResponse get(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID videoId) {
        return videos.get(current.require(jwt).id(), videoId);
    }

    /** Title / description / thumbnail. Owner only. */
    @PatchMapping("/v1/videos/{videoId}")
    VideoResponse update(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID videoId,
                         @Valid @RequestBody UpdateVideoRequest request) {
        return videos.update(current.require(jwt).id(), videoId, request);
    }

    @DeleteMapping("/v1/videos/{videoId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void delete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID videoId) {
        videos.delete(current.require(jwt).id(), videoId);
    }

    @PostMapping("/v1/videos/{videoId}/like")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void like(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID videoId) {
        videos.like(current.require(jwt).id(), videoId);
    }

    @DeleteMapping("/v1/videos/{videoId}/like")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void unlike(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID videoId) {
        videos.unlike(current.require(jwt).id(), videoId);
    }

    @PostMapping("/v1/videos/{videoId}/save")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void save(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID videoId) {
        videos.save(current.require(jwt).id(), videoId);
    }

    @DeleteMapping("/v1/videos/{videoId}/save")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void unsave(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID videoId) {
        videos.unsave(current.require(jwt).id(), videoId);
    }

    /** Idempotent per viewer — safe to call on every playback. */
    @PostMapping("/v1/videos/{videoId}/view")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void view(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID videoId) {
        videos.recordView(current.require(jwt).id(), videoId);
    }

    /** A channel's videos — the profile grid. Omit {@code kind} for both feeds. */
    @GetMapping("/v1/profiles/{profileId}/videos")
    List<VideoResponse> byChannel(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID profileId,
                                  @RequestParam(required = false) String kind,
                                  @RequestParam(defaultValue = "60") int limit) {
        return videos.byAuthor(current.require(jwt).id(), profileId, kind, limit);
    }
}

@RestController
class VideoCommentController {

    private final VideoCommentService comments;
    private final WatchCurrentProfile current;

    VideoCommentController(VideoCommentService comments, WatchCurrentProfile current) {
        this.comments = comments;
        this.current = current;
    }

    @GetMapping("/v1/videos/{videoId}/comments")
    List<VideoCommentResponse> forVideo(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID videoId) {
        return comments.forVideo(current.require(jwt).id(), videoId);
    }

    @PostMapping("/v1/videos/{videoId}/comments")
    @ResponseStatus(HttpStatus.CREATED)
    VideoCommentResponse create(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID videoId,
                                @Valid @RequestBody CreateVideoCommentRequest request) {
        return comments.create(current.require(jwt).id(), videoId, request.text());
    }

    @DeleteMapping("/v1/video-comments/{commentId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void delete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID commentId) {
        comments.delete(current.require(jwt).id(), commentId);
    }

    @PostMapping("/v1/video-comments/{commentId}/like")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void like(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID commentId) {
        comments.like(current.require(jwt).id(), commentId);
    }

    @DeleteMapping("/v1/video-comments/{commentId}/like")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void unlike(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID commentId) {
        comments.unlike(current.require(jwt).id(), commentId);
    }
}
