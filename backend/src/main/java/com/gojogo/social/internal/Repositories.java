package com.gojogo.social.internal;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.Collection;
import java.util.List;
import java.util.Set;
import java.util.UUID;

interface PostRepository extends JpaRepository<Post, UUID> {

    @Query("select p from Post p where p.authorId in :authors and p.createdAt < :before "
        + "order by p.createdAt desc, p.id desc")
    List<Post> feedByAuthors(@Param("authors") Collection<UUID> authors,
                             @Param("before") OffsetDateTime before, Pageable page);

    @Query("select p from Post p where p.createdAt < :before order by p.createdAt desc, p.id desc")
    List<Post> feedGlobal(@Param("before") OffsetDateTime before, Pageable page);

    List<Post> findByAuthorIdOrderByCreatedAtDesc(UUID authorId, Pageable page);

    long countByAuthorId(UUID authorId);

    @Modifying
    @Query("update Post p set p.likeCount = p.likeCount + :delta where p.id = :postId")
    void bumpLikeCount(@Param("postId") UUID postId, @Param("delta") int delta);

    @Modifying
    @Query("update Post p set p.commentCount = p.commentCount + :delta where p.id = :postId")
    void bumpCommentCount(@Param("postId") UUID postId, @Param("delta") int delta);
}

interface PostLikeRepository extends JpaRepository<PostLike, PostLike.Key> {

    @Query("select l.postId from PostLike l where l.userId = :userId and l.postId in :postIds")
    Set<UUID> likedPostIds(@Param("userId") UUID userId, @Param("postIds") Collection<UUID> postIds);

    @Modifying
    @Query("delete from PostLike l where l.postId = :postId and l.userId = :userId")
    int deleteByPostIdAndUserId(@Param("postId") UUID postId, @Param("userId") UUID userId);
}

interface PostBookmarkRepository extends JpaRepository<PostBookmark, PostBookmark.Key> {

    @Query("select b.postId from PostBookmark b where b.userId = :userId and b.postId in :postIds")
    Set<UUID> bookmarkedPostIds(@Param("userId") UUID userId, @Param("postIds") Collection<UUID> postIds);

    @Modifying
    @Query("delete from PostBookmark b where b.postId = :postId and b.userId = :userId")
    int deleteByPostIdAndUserId(@Param("postId") UUID postId, @Param("userId") UUID userId);
}

interface CommentRepository extends JpaRepository<Comment, UUID> {

    List<Comment> findByPostIdOrderByCreatedAtAsc(UUID postId);
}

interface CommentLikeRepository extends JpaRepository<CommentLike, CommentLike.Key> {

    @Query("select l.commentId from CommentLike l where l.userId = :userId and l.commentId in :commentIds")
    Set<UUID> likedCommentIds(@Param("userId") UUID userId, @Param("commentIds") Collection<UUID> commentIds);

    @Modifying
    @Query("delete from CommentLike l where l.commentId = :commentId and l.userId = :userId")
    int deleteByCommentIdAndUserId(@Param("commentId") UUID commentId, @Param("userId") UUID userId);
}

interface CommentLikeCountUpdater extends JpaRepository<Comment, UUID> {

    @Modifying
    @Query("update Comment c set c.likeCount = c.likeCount + :delta where c.id = :commentId")
    void bumpLikeCount(@Param("commentId") UUID commentId, @Param("delta") int delta);
}

interface FollowRepository extends JpaRepository<Follow, Follow.Key> {

    @Query("select f.followeeId from Follow f where f.followerId = :userId")
    Set<UUID> followeeIds(@Param("userId") UUID userId);

    long countByFolloweeId(UUID followeeId);

    long countByFollowerId(UUID followerId);

    @Modifying
    @Query("delete from Follow f where f.followerId = :followerId and f.followeeId = :followeeId")
    int deleteByFollowerIdAndFolloweeId(@Param("followerId") UUID followerId, @Param("followeeId") UUID followeeId);
}

interface StoryFrameRepository extends JpaRepository<StoryFrame, UUID> {

    /** The rings read: unexpired, undeleted frames, oldest first within an author. */
    @Query("select f from StoryFrame f where f.authorId in :authorIds "
        + "and f.expiresAt > :now and f.deletedAt is null order by f.createdAt asc")
    List<StoryFrame> liveByAuthors(@Param("authorIds") Collection<UUID> authorIds,
                                   @Param("now") OffsetDateTime now);

    /** Your archive — every frame you ever posted and haven't deleted, expiry ignored. */
    @Query("select f from StoryFrame f where f.authorId = :authorId and f.deletedAt is null "
        + "order by f.createdAt desc")
    List<StoryFrame> archiveOf(@Param("authorId") UUID authorId, Pageable page);

    @Query("select f from StoryFrame f where f.id in :ids and f.deletedAt is null")
    List<StoryFrame> findLiveByIds(@Param("ids") Collection<UUID> ids);
}

interface StoryViewRepository extends JpaRepository<StoryView, StoryView.Key> {

    @Query("select v.frameId from StoryView v where v.viewerId = :viewerId and v.frameId in :frameIds")
    Set<UUID> viewedFrameIds(@Param("viewerId") UUID viewerId, @Param("frameIds") Collection<UUID> frameIds);

    /** Viewer counts for a batch of frames — one query for a whole ring. */
    @Query("select v.frameId, count(v) from StoryView v where v.frameId in :frameIds group by v.frameId")
    List<Object[]> countsByFrame(@Param("frameIds") Collection<UUID> frameIds);

    List<StoryView> findByFrameIdOrderByViewedAtDesc(UUID frameId, Pageable page);
}

interface StoryReactionRepository extends JpaRepository<StoryReaction, StoryReaction.Key> {

    List<StoryReaction> findByFrameId(UUID frameId);

    @Query("select r from StoryReaction r where r.viewerId = :viewerId and r.frameId in :frameIds")
    List<StoryReaction> mineOn(@Param("viewerId") UUID viewerId, @Param("frameIds") Collection<UUID> frameIds);

    @Modifying
    @Query("delete from StoryReaction r where r.frameId = :frameId and r.viewerId = :viewerId")
    int deleteByFrameIdAndViewerId(@Param("frameId") UUID frameId, @Param("viewerId") UUID viewerId);
}

interface StoryCommentRepository extends JpaRepository<StoryComment, UUID> {

    /** The author's view: every reply on the frame. */
    List<StoryComment> findByFrameIdOrderByCreatedAtAsc(UUID frameId);

    /** A viewer's view: only what they themselves sent. */
    List<StoryComment> findByFrameIdAndAuthorIdOrderByCreatedAtAsc(UUID frameId, UUID authorId);

    @Query("select c.frameId, count(c) from StoryComment c where c.frameId in :frameIds group by c.frameId")
    List<Object[]> countsByFrame(@Param("frameIds") Collection<UUID> frameIds);
}

interface StoryMuteRepository extends JpaRepository<StoryMute, StoryMute.Key> {

    @Query("select m.mutedId from StoryMute m where m.muterId = :muterId")
    Set<UUID> mutedIds(@Param("muterId") UUID muterId);

    @Modifying
    @Query("delete from StoryMute m where m.muterId = :muterId and m.mutedId = :mutedId")
    int deleteByMuterIdAndMutedId(@Param("muterId") UUID muterId, @Param("mutedId") UUID mutedId);
}

interface CloseFriendRepository extends JpaRepository<CloseFriend, CloseFriend.Key> {

    List<CloseFriend> findByOwnerId(UUID ownerId);

    /** The rings direction: whose close-friends lists am I on? */
    @Query("select c.ownerId from CloseFriend c where c.friendId = :friendId")
    Set<UUID> ownersWhoTrust(@Param("friendId") UUID friendId);

    @Modifying
    @Query("delete from CloseFriend c where c.ownerId = :ownerId")
    void clearFor(@Param("ownerId") UUID ownerId);
}

interface StoryHighlightRepository extends JpaRepository<StoryHighlight, UUID> {

    List<StoryHighlight> findByOwnerIdOrderByCreatedAtDesc(UUID ownerId);
}

interface StoryHighlightFrameRepository extends JpaRepository<StoryHighlightFrame, StoryHighlightFrame.Key> {

    List<StoryHighlightFrame> findByHighlightIdOrderBySortOrderAsc(UUID highlightId);

    @Query("select h.highlightId, count(h) from StoryHighlightFrame h "
        + "where h.highlightId in :ids group by h.highlightId")
    List<Object[]> countsByHighlight(@Param("ids") Collection<UUID> highlightIds);

    @Modifying
    @Query("delete from StoryHighlightFrame h where h.highlightId = :highlightId")
    void clearFor(@Param("highlightId") UUID highlightId);
}
