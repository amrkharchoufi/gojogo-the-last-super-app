package com.gojogo.watch.internal;

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

interface VideoRepository extends JpaRepository<Video, UUID> {

    /** One kind's feed, newest first, keyset-paged on createdAt. */
    @Query("select v from Video v where v.kind = :kind and v.createdAt < :before "
        + "order by v.createdAt desc, v.id desc")
    List<Video> feed(@Param("kind") VideoKind kind,
                     @Param("before") OffsetDateTime before, Pageable page);

    /** A channel's own videos — the profile grid and "your videos". */
    @Query("select v from Video v where v.authorId = :authorId and v.kind = :kind "
        + "order by v.createdAt desc, v.id desc")
    List<Video> byAuthor(@Param("authorId") UUID authorId, @Param("kind") VideoKind kind, Pageable page);

    @Query("select v from Video v where v.authorId = :authorId order by v.createdAt desc, v.id desc")
    List<Video> byAuthor(@Param("authorId") UUID authorId, Pageable page);

    /** Everything the user saved, newest-saved first. */
    @Query("select v from Video v where v.id in "
        + "(select s.videoId from VideoSave s where s.userId = :userId) "
        + "order by v.createdAt desc")
    List<Video> savedBy(@Param("userId") UUID userId, Pageable page);

    @Modifying
    @Query("update Video v set v.likeCount = v.likeCount + :delta where v.id = :videoId")
    void bumpLikeCount(@Param("videoId") UUID videoId, @Param("delta") int delta);

    @Modifying
    @Query("update Video v set v.commentCount = v.commentCount + :delta where v.id = :videoId")
    void bumpCommentCount(@Param("videoId") UUID videoId, @Param("delta") int delta);

    @Modifying
    @Query("update Video v set v.viewCount = v.viewCount + 1 where v.id = :videoId")
    void bumpViewCount(@Param("videoId") UUID videoId);
}

interface VideoLikeRepository extends JpaRepository<VideoLike, VideoLike.Key> {

    @Query("select l.videoId from VideoLike l where l.userId = :userId and l.videoId in :videoIds")
    Set<UUID> likedVideoIds(@Param("userId") UUID userId, @Param("videoIds") Collection<UUID> videoIds);

    @Modifying
    @Query("delete from VideoLike l where l.videoId = :videoId and l.userId = :userId")
    int deleteByVideoIdAndUserId(@Param("videoId") UUID videoId, @Param("userId") UUID userId);
}

interface VideoSaveRepository extends JpaRepository<VideoSave, VideoSave.Key> {

    @Query("select s.videoId from VideoSave s where s.userId = :userId and s.videoId in :videoIds")
    Set<UUID> savedVideoIds(@Param("userId") UUID userId, @Param("videoIds") Collection<UUID> videoIds);

    @Modifying
    @Query("delete from VideoSave s where s.videoId = :videoId and s.userId = :userId")
    int deleteByVideoIdAndUserId(@Param("videoId") UUID videoId, @Param("userId") UUID userId);
}

interface VideoViewRepository extends JpaRepository<VideoView, VideoView.Key> {
}

interface VideoCommentRepository extends JpaRepository<VideoComment, UUID> {

    List<VideoComment> findByVideoIdOrderByCreatedAtAsc(UUID videoId);

    @Modifying
    @Query("update VideoComment c set c.likeCount = c.likeCount + :delta where c.id = :commentId")
    void bumpLikeCount(@Param("commentId") UUID commentId, @Param("delta") int delta);
}

interface VideoCommentLikeRepository extends JpaRepository<VideoCommentLike, VideoCommentLike.Key> {

    @Query("select l.commentId from VideoCommentLike l "
        + "where l.userId = :userId and l.commentId in :commentIds")
    Set<UUID> likedCommentIds(@Param("userId") UUID userId,
                              @Param("commentIds") Collection<UUID> commentIds);

    @Modifying
    @Query("delete from VideoCommentLike l where l.commentId = :commentId and l.userId = :userId")
    int deleteByCommentIdAndUserId(@Param("commentId") UUID commentId, @Param("userId") UUID userId);
}
