package com.gojogo.kyc;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/**
 * What another module may ask about a person's identity check — and it is
 * deliberately almost nothing: the answer, and whether asking is meaningful at
 * all.
 *
 * <p>This is the interface SPECS.md §4 reserved so that the IDV vendor stays a
 * config swap. Note what is <em>not</em> here: no documents, no extracted name
 * or date of birth, no vendor identifiers. A caller that could read those would
 * have to be trusted with them, and the whole reason this module exists is that
 * the platform is better off not holding them.
 */
public interface IdentityVerificationApi {

    /**
     * Whether an IDV vendor is configured at all.
     *
     * <p>The one piece of plumbing consumers legitimately need to see. Unset
     * credentials mean this platform still verifies identity the way it did
     * before the module existed — a human reading uploaded documents — and a
     * consumer that silently required a vendor verdict would make onboarding
     * impossible in an environment nobody has finished configuring.
     */
    boolean isConfigured();

    /** Never null: someone who has never been asked reads as
     *  {@link IdentityStatus#NOT_STARTED}. */
    IdentityCheck statusOf(UUID userId);

    default boolean isVerified(UUID userId) {
        return statusOf(userId).status() == IdentityStatus.VERIFIED;
    }

    /**
     * @param reason       why it was refused, in words written for the applicant
     *                     to read — the vendor's client-facing comment, not its
     *                     internal moderation note
     * @param rejectLabels the machine-readable causes, for support and metrics
     */
    record IdentityCheck(IdentityStatus status, String reason, List<String> rejectLabels,
                         OffsetDateTime verifiedAt, OffsetDateTime updatedAt) {

        public static IdentityCheck notStarted() {
            return new IdentityCheck(IdentityStatus.NOT_STARTED, null, List.of(), null, null);
        }
    }
}
