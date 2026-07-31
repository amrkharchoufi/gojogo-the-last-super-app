package com.gojogo.social.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import com.gojogo.social.CommentReplied;
import com.gojogo.social.PostCommented;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import java.util.stream.Stream;

@Service
class CommentService {

    private final CommentRepository comments;
    private final CommentLikeRepository commentLikes;
    private final CommentLikeCountUpdater likeCounts;
    private final PostRepository posts;
    private final FollowRepository follows;
    private final ProfileApi profiles;
    private final MentionService mentions;
    private final ApplicationEventPublisher events;

    CommentService(CommentRepository comments, CommentLikeRepository commentLikes,
                   CommentLikeCountUpdater likeCounts, PostRepository posts,
                   FollowRepository follows, ProfileApi profiles, MentionService mentions,
                   ApplicationEventPublisher events) {
        this.comments = comments;
        this.commentLikes = commentLikes;
        this.likeCounts = likeCounts;
        this.posts = posts;
        this.follows = follows;
        this.profiles = profiles;
        this.mentions = mentions;
        this.events = events;
    }

    /**
     * Posts a comment, or a reply when {@code parentId} is given.
     *
     * <p><b>Threads are one level deep.</b> Answering a reply attaches to that
     * reply's parent, not to the reply — so a thread stays a comment and a flat
     * run of answers under it, which is what Instagram, Threads and YouTube all
     * settled on and what a phone-width column can actually render. Who you were
     * answering is carried by the {@code @handle} the client puts in the text,
     * not by a deeper tree.
     */
    @Transactional
    CommentResponse create(UUID me, UUID postId, String text, UUID parentId) {
        Post post = posts.findById(postId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "No such post"));
        Comment parent = resolveParent(postId, parentId);
        UUID threadId = parent == null ? null : parent.getId();

        Comment comment = comments.saveAndFlush(new Comment(postId, me, text, threadId));
        posts.bumpCommentCount(postId, 1);
        if (parent != null) {
            comments.bumpReplyCount(threadId, 1);
        }

        OffsetDateTime now = OffsetDateTime.now();
        // Whoever this write is already telling by a more specific route must not
        // also get a "mentioned you" for the @handle that names them.
        Set<UUID> alreadyNotified = new HashSet<>();
        if (parent == null) {
            alreadyNotified.add(post.getAuthorId());
            // Notify the author (the notifications module ignores self-comments).
            events.publishEvent(new PostCommented(postId, post.getAuthorId(), me,
                comment.getId(), now));
        } else {
            alreadyNotified.add(parent.getAuthorId());
            events.publishEvent(new CommentReplied(postId, threadId, parent.getAuthorId(), me,
                comment.getId(), now));
        }
        List<MentionDto> tagged = mentions.record(MentionTarget.COMMENT, comment.getId(), me,
            text, postId, comment.getId(), alreadyNotified);

        return new CommentResponse(comment.getId(),
            authorSummary(me, follows.followeeIds(me)),
            comment.getText(), false, 0, comment.getCreatedAt(),
            threadId, 0, tagged, List.of());
    }

    /**
     * The thread: top-level comments oldest-first, each carrying its replies.
     * Two queries plus decoration regardless of how deep the conversation goes.
     */
    @Transactional(readOnly = true)
    List<CommentResponse> forPost(UUID me, UUID postId) {
        if (!posts.existsById(postId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such post");
        }
        List<Comment> roots = comments.findByPostIdAndParentIdIsNullOrderByCreatedAtAsc(postId);
        if (roots.isEmpty()) {
            return List.of();
        }
        List<Comment> replies = comments.findByParentIdInOrderByCreatedAtAsc(
            roots.stream().map(Comment::getId).toList());
        Decoration decoration = decorationFor(Stream.concat(roots.stream(), replies.stream()).toList(), me);
        Map<UUID, List<Comment>> byParent = replies.stream()
            .collect(Collectors.groupingBy(Comment::getParentId));
        return roots.stream()
            .map(root -> toResponse(root, decoration,
                byParent.getOrDefault(root.getId(), List.of()).stream()
                    .map(reply -> toResponse(reply, decoration, List.of()))
                    .toList()))
            .toList();
    }

    /** One comment's replies on their own — the "view all N replies" path. */
    @Transactional(readOnly = true)
    List<CommentResponse> replies(UUID me, UUID commentId) {
        if (!comments.existsById(commentId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such comment");
        }
        List<Comment> list = comments.findByParentIdOrderByCreatedAtAsc(commentId);
        if (list.isEmpty()) {
            return List.of();
        }
        Decoration decoration = decorationFor(list, me);
        return list.stream().map(c -> toResponse(c, decoration, List.of())).toList();
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

    /**
     * The comment a reply hangs off, flattened to one level. A parent from a
     * different post is a 400 rather than a silently mis-filed reply.
     */
    private Comment resolveParent(UUID postId, UUID parentId) {
        if (parentId == null) {
            return null;
        }
        Comment parent = comments.findById(parentId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "No such comment"));
        if (!parent.getPostId().equals(postId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Comment is on another post");
        }
        return parent.getParentId() == null ? parent
            : comments.findById(parent.getParentId()).orElse(parent);
    }

    /** Everything a batch of comments needs to become responses: authors, likes, tags. */
    private Decoration decorationFor(List<Comment> list, UUID me) {
        Set<UUID> commentIds = list.stream().map(Comment::getId).collect(Collectors.toSet());
        Set<UUID> authorIds = list.stream().map(Comment::getAuthorId).collect(Collectors.toSet());
        return new Decoration(
            profiles.findByIds(authorIds),
            commentLikes.likedCommentIds(me, commentIds),
            follows.followeeIds(me),
            mentions.forTargets(MentionTarget.COMMENT, commentIds));
    }

    private CommentResponse toResponse(Comment c, Decoration d, List<CommentResponse> replies) {
        return new CommentResponse(
            c.getId(),
            PostService.toAuthorSummary(d.authors().get(c.getAuthorId()), c.getAuthorId(), d.followed()),
            c.getText(),
            d.liked().contains(c.getId()),
            c.getLikeCount(),
            c.getCreatedAt(),
            c.getParentId(),
            c.getReplyCount(),
            d.mentions().getOrDefault(c.getId(), List.of()),
            replies);
    }

    /** The freshly written comment's own author, without a second round trip. */
    private AuthorSummary authorSummary(UUID me, Set<UUID> followed) {
        ProfileDto author = profiles.findById(me).orElse(null);
        return PostService.toAuthorSummary(author, me, followed);
    }

    private record Decoration(Map<UUID, ProfileDto> authors, Set<UUID> liked, Set<UUID> followed,
                              Map<UUID, List<MentionDto>> mentions) {
    }
}
