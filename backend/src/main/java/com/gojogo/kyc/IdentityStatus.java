package com.gojogo.kyc;

/**
 * Where a person's identity check stands.
 *
 * <p>Deliberately the platform's vocabulary rather than the vendor's: Sumsub
 * answers with a {@code reviewStatus} crossed with a {@code reviewAnswer} and a
 * {@code reviewRejectType}, which is three fields to describe one thing. The
 * translation happens once, inside the module, so a consumer never has to know
 * that {@code completed + RED + RETRY} means "try again" while
 * {@code completed + RED + FINAL} means "don't".
 */
public enum IdentityStatus {

    /** Never started. The default for everyone who has not been asked. */
    NOT_STARTED,
    /** Started — an applicant exists — but nothing has been submitted yet. */
    PENDING,
    /** Submitted and being checked. Nothing for the applicant to do. */
    IN_REVIEW,
    VERIFIED,
    /**
     * Refused, but fixably — a blurry document, a bad selfie. The applicant can
     * go round again with the same applicant record, which is why this is not
     * folded into {@link #REJECTED}: the app shows a retry button for one and
     * not the other.
     */
    RESUBMISSION_REQUESTED,
    /** Refused for good. Retrying is not offered; a human has to intervene. */
    REJECTED;

    /** Whether starting (or restarting) the flow makes sense from here. */
    public boolean isStartable() {
        return this == NOT_STARTED || this == PENDING || this == RESUBMISSION_REQUESTED;
    }

    /** Whether the applicant is waiting on someone else. */
    public boolean isPending() {
        return this == PENDING || this == IN_REVIEW;
    }
}
