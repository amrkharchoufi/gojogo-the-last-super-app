package com.gojogo.kyc;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Published the first time a person passes an identity check, and only then —
 * a repeated webhook for an already-verified applicant publishes nothing, so a
 * listener may treat this as "this human just became verified".
 *
 * <p>Carries no vendor identifiers and no personal data by design: a listener
 * that needs to know more should ask
 * {@link IdentityVerificationApi#statusOf(UUID)} rather than have it pushed at
 * it. First consumer is {@code partner}, which lets a held-back application
 * through.
 */
public record IdentityVerified(UUID userId, String levelName, OffsetDateTime verifiedAt) {
}
