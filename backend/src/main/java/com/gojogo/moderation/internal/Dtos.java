package com.gojogo.moderation.internal;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * What a reporter sends. {@code reason} is a word from {@link ReportReason};
 * anything unrecognised becomes {@code OTHER} rather than a 400, because a
 * report the app couldn't quite express is still a report worth having.
 */
record CreateReportRequest(@NotBlank @Size(max = 24) String targetKind,
                           @NotNull UUID targetId,
                           @Size(max = 32) String reason,
                           @Size(max = 1000) String note) {
}

/**
 * What the reporter gets back — deliberately almost nothing.
 *
 * @param alreadyReported they had already reported this. Worth saying, because
 *                        the second tap deserves reassurance rather than a
 *                        duplicate-key error; and worth saying <em>gently</em>,
 *                        because nothing about the outcome is theirs to know
 */
record ReportReceipt(UUID id, String status, boolean alreadyReported) {
}

/**
 * One row of the queue.
 *
 * @param targetSummary   the content's own first words, or null if it is gone
 * @param targetMissing   the content was deleted between the report and now —
 *                        which is an outcome, not an error
 * @param targetHidden    a moderator already hid it, so the console offers
 *                        Restore rather than Hide
 * @param otherOpenReports how many other people reported the same thing and are
 *                        still waiting; the number that turns one complaint into
 *                        a pattern
 */
record ReviewReportDto(UUID id, String targetKind, UUID targetId, String reason, String note,
                       String status, String action,
                       UUID reporterId, String reporterHandle,
                       UUID targetOwnerId, String targetOwnerHandle,
                       String targetSummary, boolean targetMissing, boolean targetHidden,
                       int otherOpenReports,
                       String reviewedBy, OffsetDateTime reviewedAt, String reviewNote,
                       OffsetDateTime createdAt) {
}

/** @param action HIDE | REMOVE | SUSPEND | RESTORE */
record ModerationDecisionRequest(@NotBlank @Size(max = 16) String action,
                                 @Size(max = 1000) String note) {
}

record DismissRequest(@Size(max = 1000) String note) {
}

/** The one number a console's badge reads. */
record QueueSummary(long open) {
}
