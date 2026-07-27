package com.gojogo.partner;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Published when a human decides an application: approved, rejected, suspended,
 * or restored. One event rather than four, because every consumer so far cares
 * about the same three things — who, what happened, and what to say about it.
 *
 * <p>First consumer: {@code notifications}, which pushes the decision to the
 * applicant's devices. A rejection is the one notification in this product that
 * carries a reason, so {@link #note} is part of the contract rather than an
 * internal field.
 *
 * @param status  the new {@code PartnerStatus} name — APPROVED / REJECTED /
 *                SUSPENDED / APPROVED again on a restore
 * @param refId   what the approval provisioned (a delivery merchant id), or
 *                null when nothing was
 */
public record PartnerReviewed(UUID accountId, UUID userId, String kind, String businessName,
                              String status, UUID refId, String note,
                              OffsetDateTime reviewedAt) {
}
