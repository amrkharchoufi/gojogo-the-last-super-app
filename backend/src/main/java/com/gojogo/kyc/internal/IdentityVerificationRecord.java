package com.gojogo.kyc.internal;

import com.gojogo.kyc.IdentityStatus;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

/**
 * What the platform keeps about one person's identity check: the verdict, the
 * handle needed to ask again, and enough to explain a refusal.
 *
 * <p>Named {@code …Record} rather than {@code IdentityVerification} so nothing
 * here shadows the public {@code IdentityVerificationApi.IdentityCheck} a
 * consumer sees — and to make the distinction the module rests on hard to lose:
 * this row is a <em>record of a decision</em>, not the evidence behind it. The
 * documents, the selfie and the extracted personal data stay with the vendor.
 */
@Entity
@Table(name = "identity_verification", schema = "kyc")
class IdentityVerificationRecord {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "user_id", nullable = false, updatable = false)
    private UUID userId;

    @Column(name = "provider", nullable = false)
    private String provider = "SUMSUB";

    @Column(name = "applicant_id")
    private String applicantId;

    @Column(name = "level_name", nullable = false)
    private String levelName = "";

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private IdentityStatus status = IdentityStatus.NOT_STARTED;

    @Column(name = "reason")
    private String reason;

    @Column(name = "moderation_note")
    private String moderationNote;

    @Column(name = "reject_labels", nullable = false)
    private String rejectLabels = "";

    @Column(name = "provider_event_at")
    private OffsetDateTime providerEventAt;

    @Column(name = "verified_at")
    private OffsetDateTime verifiedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt = OffsetDateTime.now();

    protected IdentityVerificationRecord() {
    }

    IdentityVerificationRecord(UUID userId, String levelName) {
        this.userId = userId;
        this.levelName = levelName == null ? "" : levelName;
    }

    /** Records that the applicant has been handed a token and may now start.
     *  Only ever moves someone off the starting line — re-opening the flow
     *  after a verdict must not erase it. */
    void starting(String levelName) {
        if (levelName != null && !levelName.isBlank()) this.levelName = levelName;
        if (status == IdentityStatus.NOT_STARTED) {
            this.status = IdentityStatus.PENDING;
        }
        touch();
    }

    /**
     * Applies a verdict from the vendor.
     *
     * @return true if this actually changed the answer — the caller uses it to
     *         decide whether a domain event is warranted, so a retried webhook
     *         stays silent
     */
    boolean apply(SumsubVerdict verdict) {
        if (isStale(verdict)) return false;
        IdentityStatus previous = status;
        if (verdict.applicantId() != null) this.applicantId = verdict.applicantId();
        if (!verdict.levelName().isBlank()) this.levelName = verdict.levelName();
        this.status = verdict.status();
        this.reason = trim(verdict.clientComment(), 600);
        this.moderationNote = trim(verdict.moderationComment(), 600);
        this.rejectLabels = trim(String.join(",", verdict.rejectLabels()), 400);
        if (verdict.eventAt() != null) this.providerEventAt = verdict.eventAt();
        // The constraint in V21 is the real rule: VERIFIED iff verified_at.
        // Keep the first time they passed, not the latest webhook that says so.
        if (status == IdentityStatus.VERIFIED) {
            if (verifiedAt == null) {
                verifiedAt = verdict.eventAt() == null ? OffsetDateTime.now() : verdict.eventAt();
            }
        } else {
            verifiedAt = null;
        }
        touch();
        return previous != status;
    }

    /**
     * Whether this verdict is older than what we already have.
     *
     * <p>Webhook deliveries are not ordered, and Sumsub retries. Without this, a
     * delayed {@code applicantPending} landing after {@code applicantReviewed}
     * would quietly un-verify someone who had already passed.
     */
    private boolean isStale(SumsubVerdict verdict) {
        return verdict.eventAt() != null && providerEventAt != null
            && verdict.eventAt().isBefore(providerEventAt);
    }

    private void touch() {
        this.updatedAt = OffsetDateTime.now();
    }

    private static String trim(String value, int max) {
        if (value == null || value.isBlank()) return value == null ? null : value;
        String clean = value.trim();
        return clean.length() <= max ? clean : clean.substring(0, max);
    }

    UUID getUserId() { return userId; }
    String getProvider() { return provider; }
    String getApplicantId() { return applicantId; }
    String getLevelName() { return levelName; }
    IdentityStatus getStatus() { return status; }
    String getReason() { return reason; }
    String getModerationNote() { return moderationNote; }
    OffsetDateTime getVerifiedAt() { return verifiedAt; }
    OffsetDateTime getUpdatedAt() { return updatedAt; }

    /** The refusal causes, deduped and in the order the vendor gave them. */
    List<String> rejectLabelList() {
        return Arrays.stream(rejectLabels.split(",")).map(String::trim)
            .filter(label -> !label.isEmpty()).distinct().toList();
    }
}
