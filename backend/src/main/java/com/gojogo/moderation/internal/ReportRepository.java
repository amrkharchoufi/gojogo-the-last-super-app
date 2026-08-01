package com.gojogo.moderation.internal;

import com.gojogo.moderation.ModerationTargetKind;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

interface ReportRepository extends JpaRepository<Report, UUID> {

    Optional<Report> findByReporterIdAndTargetKindAndTargetId(
        UUID reporterId, ModerationTargetKind targetKind, UUID targetId);

    /** The queue: oldest first, because the thing nobody has looked at yet is
     *  the thing that matters. */
    @Query("select r from Report r where r.status = :status order by r.createdAt asc")
    List<Report> byStatus(@Param("status") ReportStatus status, Pageable page);

    @Query("select r from Report r where r.status = :status and r.targetKind = :kind "
        + "order by r.createdAt asc")
    List<Report> byStatusAndKind(@Param("status") ReportStatus status,
                                 @Param("kind") ModerationTargetKind kind, Pageable page);

    /**
     * Every open report against one piece of content. Deciding once closes all
     * of them: forty rows for one viral post is a queue nobody can work, and the
     * thirty-nine reporters after the first were right about the same thing.
     */
    List<Report> findByTargetKindAndTargetIdAndStatus(
        ModerationTargetKind targetKind, UUID targetId, ReportStatus status);

    /** Everything ever filed against one account — the context a suspension
     *  decision is made in, rather than the single report in front of you. */
    @Query("select r from Report r where r.targetOwnerId = :ownerId order by r.createdAt desc")
    List<Report> againstOwner(@Param("ownerId") UUID ownerId, Pageable page);

    long countByStatus(ReportStatus status);
}
