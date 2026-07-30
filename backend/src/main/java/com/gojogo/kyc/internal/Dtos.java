package com.gojogo.kyc.internal;

import java.time.OffsetDateTime;
import java.util.List;

/**
 * A person's identity check as they are allowed to see it.
 *
 * @param status       one of {@link com.gojogo.kyc.IdentityStatus}
 * @param reason       why it was refused, in the vendor's client-facing words —
 *                     never the internal moderation note
 * @param rejectLabels the machine-readable causes, so the app can say something
 *                     better than the generic sentence when it recognises one
 * @param levelName    which check they were put through
 * @param available    whether identity verification is configured at all. False
 *                     means this environment still proves identity by document
 *                     upload and human review, and the app should not offer a
 *                     button that cannot work.
 * @param canStart     whether launching the SDK makes sense right now — false
 *                     while a verdict is pending and once it is decided
 */
record IdentityVerificationDto(String status, String reason, List<String> rejectLabels,
                               String levelName, boolean available, boolean canStart,
                               OffsetDateTime verifiedAt, OffsetDateTime updatedAt) {
}

/**
 * The token the mobile SDK launches with, plus the state it is launching into.
 *
 * <p>The verification travels with the token so the app can render the result
 * screen without a second round trip — and so a client that asked for a token it
 * turns out not to need can see that immediately.
 */
record AccessTokenResponse(String token, String levelName, IdentityVerificationDto verification) {
}
