package com.gojogo.watch.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Comments on a video.
 *
 * <p>Watch keeps its own comment table rather than borrowing social's: a
 * comment belongs to the thing it is on, and reaching into {@code social}'s
 * tables to make them polymorphic is exactly the boundary crossing the module
 * structure exists to prevent.
 */
@Service
class VideoCommentService {

    private final VideoCommentRepository comments;
    private final VideoCommentLikeRepository commentLikes;
    private final VideoRepository videos;
    private final VideoService videoService;
    private final ProfileApi profiles;

    VideoCommentService(VideoCommentRepository comments, VideoCommentLikeRepository commentLikes,
                        VideoRepository videos, VideoService videoService, ProfileApi profiles) {
        this.comments = comments;
        this.commentLikes = commentLikes;
        this.videos = videos;
        this.videoService = videoService;
        this.profiles = profiles;
    }

    @Transactional(readOnly = true)
    List<VideoCommentResponse> forVideo(UUID me, UUID videoId) {
        requireVideo(videoId);
        return decorate(comments.findByVideoIdOrderByCreatedAtAsc(videoId), me);
    }

    @Transactional
    VideoCommentResponse create(UUID me, UUID videoId, String text) {
        requireVideo(videoId);
        VideoComment comment = comments.save(new VideoComment(videoId, me, text));
        videos.bumpCommentCount(videoId, 1);
        return decorate(List.of(comment), me).getFirst();
    }

    @Transactional
    void delete(UUID me, UUID commentId) {
        VideoComment comment = comments.findById(commentId).orElseThrow(
            () -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such comment"));
        // Your own comment, or any comment on your own video.
        boolean mine = comment.getAuthorId().equals(me);
        boolean onMyVideo = videos.findById(comment.getVideoId())
            .map(v -> v.getAuthorId().equals(me)).orElse(false);
        if (!mine && !onMyVideo) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your comment");
        }
        comments.delete(comment);
        videos.bumpCommentCount(comment.getVideoId(), -1);
    }

    @Transactional
    void like(UUID me, UUID commentId) {
        requireComment(commentId);
        try {
            commentLikes.saveAndFlush(new VideoCommentLike(commentId, me));
            comments.bumpLikeCount(commentId, 1);
        } catch (DataIntegrityViolationException alreadyLiked) {
            // idempotent
        }
    }

    @Transactional
    void unlike(UUID me, UUID commentId) {
        if (commentLikes.deleteByCommentIdAndUserId(commentId, me) > 0) {
            comments.bumpLikeCount(commentId, -1);
        }
    }

    private List<VideoCommentResponse> decorate(List<VideoComment> list, UUID me) {
        if (list.isEmpty()) {
            return List.of();
        }
        Set<UUID> commentIds = list.stream().map(VideoComment::getId).collect(Collectors.toSet());
        Set<UUID> authorIds = list.stream().map(VideoComment::getAuthorId).collect(Collectors.toSet());
        Map<UUID, ProfileDto> authors = profiles.findByIds(authorIds);
        Map<UUID, Long> followers = videoService.followerCounts(authorIds);
        Set<UUID> followed = videoService.followeeIds(me);
        Set<UUID> liked = commentLikes.likedCommentIds(me, commentIds);
        return list.stream().map(c -> new VideoCommentResponse(
            c.getId(),
            videoService.channel(authors.get(c.getAuthorId()), c.getAuthorId(), followers, followed),
            c.getText(),
            liked.contains(c.getId()),
            c.getLikeCount(),
            c.getCreatedAt())).toList();
    }

    private void requireVideo(UUID videoId) {
        if (!videos.existsById(videoId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such video");
        }
    }

    private void requireComment(UUID commentId) {
        if (!comments.existsById(commentId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such comment");
        }
    }
}
