package com.gojogo.watch.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import com.gojogo.social.SocialGraphApi;
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
    private final SocialGraphApi graph;

    VideoCommentService(VideoCommentRepository comments, VideoCommentLikeRepository commentLikes,
                        VideoRepository videos, VideoService videoService, ProfileApi profiles,
                        SocialGraphApi graph) {
        this.comments = comments;
        this.commentLikes = commentLikes;
        this.videos = videos;
        this.videoService = videoService;
        this.profiles = profiles;
        this.graph = graph;
    }

    @Transactional(readOnly = true)
    List<VideoCommentResponse> forVideo(UUID me, UUID videoId) {
        videoService.requireVisible(me, videoId);
        // Blocked commenters drop out of the thread, same as they do in social's
        // (2e M5). No hidden flag here: a video comment isn't a moderation
        // target — a report against a video is a report against the video.
        Set<UUID> hidden = graph.blockedIds(me);
        List<VideoComment> visible = comments.findByVideoIdOrderByCreatedAtAsc(videoId).stream()
            .filter(c -> !hidden.contains(c.getAuthorId()))
            .toList();
        return decorate(visible, me);
    }

    @Transactional
    VideoCommentResponse create(UUID me, UUID videoId, String text) {
        videoService.requireVisible(me, videoId);
        VideoComment comment = comments.save(new VideoComment(videoId, me, text));
        videos.bumpCommentCount(videoId, 1);
        return decorate(List.of(comment), me).getFirst();
    }

    @Transactional
    void delete(UUID me, UUID commentId) {
        VideoComment comment = comments.findById(commentId).orElseThrow(
            () -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such comment"));
        // Your own comment, or any comment on your own video.
        boolean mine = profiles.actsFor(me, comment.getAuthorId());
        boolean onMyVideo = videos.findById(comment.getVideoId())
            .map(v -> profiles.actsFor(me, v.getAuthorId())).orElse(false);
        if (!mine && !onMyVideo) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your comment");
        }
        comments.delete(comment);
        videos.bumpCommentCount(comment.getVideoId(), -1);
    }

    @Transactional
    void like(UUID me, UUID commentId) {
        VideoComment comment = comments.findById(commentId).orElseThrow(
            () -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such comment"));
        if (graph.blockedBetween(me, comment.getAuthorId())) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such comment");
        }
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

}
