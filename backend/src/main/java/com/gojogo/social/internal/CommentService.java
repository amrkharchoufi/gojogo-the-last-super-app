package com.gojogo.social.internal;

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

@Service
class CommentService {

    private final CommentRepository comments;
    private final CommentLikeRepository commentLikes;
    private final CommentLikeCountUpdater likeCounts;
    private final PostRepository posts;
    private final FollowRepository follows;
    private final ProfileApi profiles;

    CommentService(CommentRepository comments, CommentLikeRepository commentLikes,
                   CommentLikeCountUpdater likeCounts, PostRepository posts,
                   FollowRepository follows, ProfileApi profiles) {
        this.comments = comments;
        this.commentLikes = commentLikes;
        this.likeCounts = likeCounts;
        this.posts = posts;
        this.follows = follows;
        this.profiles = profiles;
    }

    @Transactional
    CommentResponse create(UUID me, UUID postId, String text) {
        if (!posts.existsById(postId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such post");
        }
        Comment comment = comments.save(new Comment(postId, me, text));
        posts.bumpCommentCount(postId, 1);
        return toResponses(List.of(comment), me).getFirst();
    }

    @Transactional(readOnly = true)
    List<CommentResponse> forPost(UUID me, UUID postId) {
        if (!posts.existsById(postId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such post");
        }
        return toResponses(comments.findByPostIdOrderByCreatedAtAsc(postId), me);
    }

    @Transactional
    void like(UUID me, UUID commentId) {
        if (!comments.existsById(commentId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such comment");
        }
        try {
            commentLikes.saveAndFlush(new CommentLike(commentId, me));
            likeCounts.bumpLikeCount(commentId, 1);
        } catch (DataIntegrityViolationException alreadyLiked) {
            // idempotent
        }
    }

    @Transactional
    void unlike(UUID me, UUID commentId) {
        if (commentLikes.deleteByCommentIdAndUserId(commentId, me) > 0) {
            likeCounts.bumpLikeCount(commentId, -1);
        }
    }

    private List<CommentResponse> toResponses(List<Comment> list, UUID me) {
        if (list.isEmpty()) {
            return List.of();
        }
        Set<UUID> commentIds = list.stream().map(Comment::getId).collect(Collectors.toSet());
        Set<UUID> authorIds = list.stream().map(Comment::getAuthorId).collect(Collectors.toSet());
        Map<UUID, ProfileDto> authors = profiles.findByIds(authorIds);
        Set<UUID> liked = commentLikes.likedCommentIds(me, commentIds);
        Set<UUID> followed = follows.followeeIds(me);
        return list.stream().map(c -> new CommentResponse(
            c.getId(),
            PostService.toAuthorSummary(authors.get(c.getAuthorId()), c.getAuthorId(), followed),
            c.getText(),
            liked.contains(c.getId()),
            c.getLikeCount(),
            c.getCreatedAt())).toList();
    }
}
