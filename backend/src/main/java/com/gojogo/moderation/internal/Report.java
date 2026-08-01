package com.gojogo.moderation.internal;

import com.gojogo.moderation.ModerationAction;
import com.gojogo.moderation.ModerationTargetKind;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/** One person telling us about one thing. See V28 for why the columns are shaped this way. */
@Entity
@Table(name = "report", schema = "moderation")
class Report {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "reporter_id", nullable = false)
    private UUID reporterId;

    @Enumerated(EnumType.STRING)
    @Column(name = "target_kind", nullable = false, length = 24)
    private ModerationTargetKind targetKind;

    @Column(name = "target_id", nullable = false)
    private UUID targetId;

    /** Resolved from the vertical at report time — see V28. */
    @Column(name = "target_owner_id")
    private UUID targetOwnerId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    private ReportReason reason;

    @Column(nullable = false, length = 1000)
    private String note = "";

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private ReportStatus status = ReportStatus.OPEN;

    @Enumerated(EnumType.STRING)
    @Column(length = 16)
    private ModerationAction action;

    @Column(name = "reviewed_by", length = 200)
    private String reviewedBy;

    @Column(name = "reviewed_at")
    private OffsetDateTime reviewedAt;

    @Column(name = "review_note", length = 1000)
    private String reviewNote;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected Report() {
    }

    Report(UUID reporterId, ModerationTargetKind targetKind, UUID targetId, UUID targetOwnerId,
           ReportReason reason, String note) {
        this.reporterId = reporterId;
        this.targetKind = targetKind;
        this.targetId = targetId;
        this.targetOwnerId = targetOwnerId;
        this.reason = reason;
        this.note = note == null ? "" : note;
        this.createdAt = OffsetDateTime.now();
    }

    /** Closes the report with a decision. The action is recorded even for
     *  {@code RESTORE}, so the trail reads as a sequence rather than a state. */
    void resolve(ReportStatus outcome, ModerationAction action, String who, String note) {
        this.status = outcome;
        this.action = action;
        this.reviewedBy = who;
        this.reviewedAt = OffsetDateTime.now();
        this.reviewNote = note == null || note.isBlank() ? null : note.trim();
    }

    UUID getId() {
        return id;
    }

    UUID getReporterId() {
        return reporterId;
    }

    ModerationTargetKind getTargetKind() {
        return targetKind;
    }

    UUID getTargetId() {
        return targetId;
    }

    UUID getTargetOwnerId() {
        return targetOwnerId;
    }

    ReportReason getReason() {
        return reason;
    }

    String getNote() {
        return note;
    }

    ReportStatus getStatus() {
        return status;
    }

    ModerationAction getAction() {
        return action;
    }

    String getReviewedBy() {
        return reviewedBy;
    }

    OffsetDateTime getReviewedAt() {
        return reviewedAt;
    }

    String getReviewNote() {
        return reviewNote;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }
}
