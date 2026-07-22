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

    List<StoryFrame> findByAuthorIdInAndExpiresAtAfterOrderByCreatedAtAsc(
        Collection<UUID> authorIds, OffsetDateTime now);
}

interface StoryViewRepository extends JpaRepository<StoryView, StoryView.Key> {

    @Query("select v.frameId from StoryView v where v.viewerId = :viewerId and v.frameId in :frameIds")
    Set<UUID> viewedFrameIds(@Param("viewerId") UUID viewerId, @Param("frameIds") Collection<UUID> frameIds);
}
