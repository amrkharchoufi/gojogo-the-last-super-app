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
    private final BlockService blocks;
    private final ProfileApi profiles;
    private final MentionService mentions;
    private final ApplicationEventPublisher events;

    CommentService(CommentRepository comments, CommentLikeRepository commentLikes,
                   CommentLikeCountUpdater likeCounts, PostRepository posts,
                   FollowRepository follows, BlockService blocks, ProfileApi profiles,
                   MentionService mentions, ApplicationEventPublisher events) {
        this.comments = comments;
        this.commentLikes = commentLikes;
        this.likeCounts = likeCounts;
        this.posts = posts;
        this.follows = follows;
        this.blocks = blocks;
        this.profiles = profiles;
        this.mentions = mentions;
        this.events = events;
    }

    /**
     * Posts a comment, or a reply when {@code parentId} is given.
     *
     * <p><b>Threads are one level deep, but "who you answered" is not the same
     * question as "where the row is filed".</b> A reply to a reply is stored
     * under their shared top-level parent — that flattening is what Instagram,
     * Threads and YouTube all settled on, and what a phone-width column can
     * actually render. It must not decide who gets told: answering B's reply
     * inside A's thread is addressed to <em>B</em>, and notifying A instead
     * would tell the wrong person while leaving the right one in silence.
     * {@code addressee} is therefore the comment that was actually tapped, and
     * {@code threadId} only says where it lands.
     */
    @Transactional
    CommentResponse create(UUID me, UUID postId, String text, UUID parentId) {
        Post post = posts.findById(postId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "No such post"));
        requireVisible(me, post);
        Comment addressee = resolveAddressee(postId, parentId);
        // You can comment under a post whose author you have no quarrel with and
        // still be answering somebody you blocked. 404 on the parent, because
        // from your side that comment does not exist.
        if (addressee != null && blocks.between(me, addressee.getAuthorId())) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such comment");
        }
        UUID threadId = addressee == null ? null : threadRootOf(addressee);

        Comment comment = comments.saveAndFlush(new Comment(postId, me, text, threadId));
        posts.bumpCommentCount(postId, 1);
        if (threadId != null) {
            comments.bumpReplyCount(threadId, 1);
        }

        OffsetDateTime now = OffsetDateTime.now();
        // Resolved before anything is published, because who is tagged decides
        // what the author is told — see below.
        List<MentionDto> tagged = mentions.resolve(MentionTarget.COMMENT, text);
        Set<UUID> taggedIds = tagged.stream().map(MentionDto::profileId).collect(Collectors.toSet());

        // Whoever this write is already telling by a more specific route must not
        // also get a "mentioned you" for the @handle that names them.
        Set<UUID> alreadyNotified = new HashSet<>();
        if (addressee == null) {
            // <b>A comment that @-names the post's author is a mention.</b> It
            // is the more specific fact and the one the author cares about:
            // "commented on your post" under a post with forty comments says
            // nothing, while "mentioned you in a comment" is addressed to them.
            // Only the top-level case swaps. A reply already carries the handle
            // it answers — the compose box types it for you — so treating that
            // as a tag would retire "replied to your comment" entirely.
            if (!taggedIds.contains(post.getAuthorId())) {
                alreadyNotified.add(post.getAuthorId());
                // Notify the author (the notifications module ignores self-comments).
                events.publishEvent(new PostCommented(postId, post.getAuthorId(), me,
                    comment.getId(), now));
            }
        } else {
            alreadyNotified.add(addressee.getAuthorId());
            events.publishEvent(new CommentReplied(postId, addressee.getId(),
                addressee.getAuthorId(), me, comment.getId(), now));
        }
        mentions.record(MentionTarget.COMMENT, comment.getId(), me,
            tagged, postId, comment.getId(), alreadyNotified);

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
        Post post = posts.findById(postId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "No such post"));
        requireVisible(me, post);
        List<Comment> roots = visibleTo(me,
            comments.findByPostIdAndParentIdIsNullOrderByCreatedAtAsc(postId));
        if (roots.isEmpty()) {
            return List.of();
        }
        List<Comment> replies = visibleTo(me, comments.findByParentIdInOrderByCreatedAtAsc(
            roots.stream().map(Comment::getId).toList()));
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
        List<Comment> list = visibleTo(me, comments.findByParentIdOrderByCreatedAtAsc(commentId));
        if (list.isEmpty()) {
            return List.of();
        }
        Decoration decoration = decorationFor(list, me);
        return list.stream().map(c -> toResponse(c, decoration, List.of())).toList();
    }

    @Transactional
    void like(UUID me, UUID commentId) {
        Comment comment = comments.findById(commentId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "No such comment"));
        if (blocks.between(me, comment.getAuthorId())
            || (comment.isHidden() && !comment.getAuthorId().equals(me))) {
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
     * The comment being answered — exactly the one the client named, at whatever
     * depth it sits. This is the notification's recipient, so it is deliberately
     * <em>not</em> flattened. A parent from a different post is a 400 rather than
     * a silently mis-filed reply.
     */
    private Comment resolveAddressee(UUID postId, UUID parentId) {
        if (parentId == null) {
            return null;
        }
        Comment parent = comments.findById(parentId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "No such comment"));
        if (!parent.getPostId().equals(postId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Comment is on another post");
        }
        return parent;
    }

    /**
     * Where a reply to {@code addressee} is filed: the addressee itself when it
     * is top-level, otherwise its parent. Falls back to the addressee if that
     * parent has vanished mid-write, so the reply lands somewhere real rather
     * than dangling.
     */
    private UUID threadRootOf(Comment addressee) {
        UUID parentId = addressee.getParentId();
        if (parentId == null) {
            return addressee.getId();
        }
        return comments.existsById(parentId) ? parentId : addressee.getId();
    }

    /**
     * The thread as this reader may see it: no comments by (or to) anyone a
     * block stands between, and no comment a moderator hid — except the
     * reader's own, which they keep seeing so a takedown isn't silent.
     *
     * <p>Filtered here rather than in the query because a thread is fetched
     * whole and unpaged, so nothing can be thrown off by removing rows. The one
     * knock-on is that {@code replyCount} still counts what it always counted:
     * making it per-viewer would be a query per row, and a "3 replies" that
     * opens two is a smaller wrong than a thread that takes a second to load.
     */
    private List<Comment> visibleTo(UUID me, List<Comment> list) {
        if (list.isEmpty()) {
            return list;
        }
        Set<UUID> hidden = blocks.hiddenFrom(me);
        return list.stream()
            .filter(c -> !hidden.contains(c.getAuthorId()))
            .filter(c -> !c.isHidden() || c.getAuthorId().equals(me))
            .toList();
    }

    /** A post you cannot see has no comments you can see either — and says so
     *  with the same 404 the post itself gives. */
    private void requireVisible(UUID me, Post post) {
        if (blocks.between(me, post.getAuthorId())
            || (post.isHidden() && !post.getAuthorId().equals(me))) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such post");
        }
    }

    /** Moderation's takedown (2e M5) — see {@code ModeratableContent}. */
    @Transactional
    void setHidden(UUID commentId, boolean hidden) {
        comments.findById(commentId).ifPresent(c -> {
            c.setHidden(hidden);
            comments.save(c);
        });
    }

    @Transactional
    void removeAsModerator(UUID commentId) {
        comments.findById(commentId).ifPresent(c -> {
            posts.bumpCommentCount(c.getPostId(), -1);
            if (c.getParentId() != null) {
                comments.bumpReplyCount(c.getParentId(), -1);
            }
            comments.delete(c);
        });
    }

    @Transactional(readOnly = true)
    java.util.Optional<Comment> find(UUID commentId) {
        return comments.findById(commentId);
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
