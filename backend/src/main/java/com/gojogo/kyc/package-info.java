/**
 * KYC module — identity verification through an external IDV vendor
 * ({@code kyc} schema). A <em>platform</em> capability (ARCHITECTURE.md §2):
 * proving a human is who they claim is needed by partner onboarding today, by
 * driver staking and payouts in Phase 3, and by sellers and service providers in
 * Phase 5 — so it is not owned by any one of them.
 *
 * <p>This is impl #2 of the {@code IdentityVerificationApi} SPECS.md §4
 * reserved. Impl #1 — an applicant uploads an ID card into a private prefix and
 * a human decides — still exists inside {@code partner}, and still runs whenever
 * this module is unconfigured. That is the whole reason the interface is here:
 * the vendor is a config swap, and an environment with no Sumsub credentials
 * behaves exactly as it did before this module existed.
 *
 * <p><strong>The module stores a verdict, not evidence.</strong> Documents, the
 * selfie, the liveness video and the extracted personal data stay with the
 * vendor. Keeping a second copy of everyone's passport is the risk that using an
 * IDV vendor is meant to remove, so what is persisted is the answer, the handle
 * needed to re-ask, and enough to tell the applicant why not.
 *
 * <p>Two ways a verdict arrives, and both matter:
 * <ul>
 *   <li>a <b>webhook</b> ({@code /v1/kyc/webhook}) — the fast path, HMAC-verified
 *       against the raw request body and idempotent on the delivery id;</li>
 *   <li>a <b>pull</b> ({@code POST /v1/kyc/refresh}) — the fallback, because a
 *       webhook needs a public URL configured in someone else's console and a
 *       KYC flow must not be undeliverable until it is.</li>
 * </ul>
 *
 * <p>Consumers read {@link com.gojogo.kyc.IdentityVerificationApi} or listen for
 * {@link com.gojogo.kyc.IdentityVerified}. Nothing outside this module talks to
 * the vendor.
 */
@org.springframework.modulith.ApplicationModule(displayName = "KYC")
package com.gojogo.kyc;
