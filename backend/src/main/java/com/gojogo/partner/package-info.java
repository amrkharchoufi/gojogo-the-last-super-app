/**
 * Partner module — business onboarding and KYC ({@code partner} schema). A
 * platform capability (ARCHITECTURE.md §2/§10): it owns the <em>relationship</em>
 * between the platform and a business, not anything that business sells.
 *
 * <p>An application carries a business identity, a set of identity documents,
 * and a status a human moves. On approval the module <em>provisions</em> into
 * whichever vertical the application's {@code kind} names — today only
 * {@code RESTAURANT}, through
 * {@link com.gojogo.delivery.MerchantProvisioningApi}. {@code DRIVER} and
 * {@code COURIER} are the same application with nowhere to land until the
 * Phase 3 {@code dispatch} module exists, so they are accepted, reviewed, and
 * rejected at approval time rather than half-provisioned.
 *
 * <p>The dependency runs one way — {@code partner → delivery}, over delivery's
 * public API. Delivery keeps no idea that onboarding exists; all that survives
 * into it is an {@code ownerId} on the merchant row, which is what lets it
 * authorise "edit my own restaurant" without asking anyone about KYC.
 *
 * <p><strong>One thing arrives the other way, and it is an event.</strong> Phase
 * 3 M5's community vehicle verification starts when a trip ends, so this module
 * <em>listens</em> for {@code travel.TripCompleted} rather than being called by
 * it. That direction is deliberate: a trip ending is a fact about a trip, and
 * whether it starts a vehicle check is entirely this module's business — nothing
 * about the ride changes if the invitation is never created, which is precisely
 * what makes an event the right shape and a call the wrong one.
 *
 * <p><strong>Who proves identity.</strong> Personal identity is
 * {@link com.gojogo.kyc.IdentityVerificationApi}'s job — an IDV vendor matching
 * a real document to a live face, which no reviewer does well from a phone
 * photo. This module keeps the question a vendor cannot answer: whether this
 * <em>business</em> should trade here. So a vendor verdict is a precondition for
 * submitting an application, and approval remains a human act. On an environment
 * with no vendor configured the identity documents come back into the required
 * list and the reviewer decides both halves, exactly as before.
 *
 * <p>The business documents that remain are <strong>private</strong>. They go
 * through {@link com.gojogo.media.MediaDocumentApi}, never
 * {@code /v1/media/presign}, because everything the latter mints is
 * world-readable from S3 today. The module stores object keys, and a reviewer
 * reads one through a 10-minute presigned GET.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Partner")
package com.gojogo.partner;
