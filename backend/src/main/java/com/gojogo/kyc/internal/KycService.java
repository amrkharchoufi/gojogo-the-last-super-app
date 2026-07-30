package com.gojogo.kyc.internal;

import com.fasterxml.jackson.databind.JsonNode;
import com.gojogo.kyc.IdentityStatus;
import com.gojogo.kyc.IdentityVerificationApi;
import com.gojogo.kyc.IdentityVerified;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

/**
 * Identity verification as the rest of the platform experiences it: start a
 * check, ask how it went, and be told when it passes.
 *
 * <p>Two things arrive from outside and both land here — a webhook Sumsub
 * pushes, and a pull this backend runs. They converge on {@link #record} so the
 * staleness rule, the idempotency rule and the domain event exist once. A
 * verdict that came in by the slow path is indistinguishable from one that came
 * in by the fast path, which is what makes the webhook optional rather than
 * load-bearing.
 */
@Service
class KycService implements IdentityVerificationApi {

    private static final Logger log = LoggerFactory.getLogger(KycService.class);

    private final IdentityVerificationRepository verifications;
    private final ProviderEventRepository events;
    private final SumsubClient sumsub;
    private final ApplicationEventPublisher publisher;

    KycService(IdentityVerificationRepository verifications, ProviderEventRepository events,
               SumsubClient sumsub, ApplicationEventPublisher publisher) {
        this.verifications = verifications;
        this.events = events;
        this.sumsub = sumsub;
        this.publisher = publisher;
    }

    // MARK: The public API

    @Override
    public boolean isConfigured() {
        return sumsub.enabled();
    }

    @Override
    @Transactional(readOnly = true)
    public IdentityCheck statusOf(UUID userId) {
        return verifications.findByUserId(userId).map(KycService::toCheck)
            .orElseGet(IdentityCheck::notStarted);
    }

    // MARK: The applicant's side

    /**
     * A token for the mobile SDK, and the row that says this person has begun.
     *
     * <p>Minted per launch and short-lived — the SDK asks for another through
     * its expiration handler rather than holding one open, so this endpoint is
     * called more than once per verification and must stay idempotent.
     */
    @Transactional
    AccessTokenResponse startVerification(UUID userId) {
        String token = sumsub.createAccessToken(userId);
        IdentityVerificationRecord record = verifications.findByUserId(userId)
            .orElseGet(() -> verifications.save(
                new IdentityVerificationRecord(userId, sumsub.levelName())));
        record.starting(sumsub.levelName());
        return new AccessTokenResponse(token, sumsub.levelName(), toDto(record));
    }

    /**
     * Asks Sumsub directly where this person stands.
     *
     * <p>The fallback that keeps the flow honest: a webhook needs a public URL
     * configured in someone else's console, and until it is — or when a delivery
     * is lost — this is how a verdict gets in. The app calls it when the SDK
     * closes, which is exactly the moment the answer usually changes.
     */
    @Transactional
    IdentityVerificationDto refresh(UUID userId) {
        if (!sumsub.enabled()) {
            return toDto(verifications.findByUserId(userId).orElse(null));
        }
        SumsubVerdict verdict = sumsub.fetchApplicant(userId);
        if (verdict == null) {
            // Never started on their side, or unreachable. Either way the local
            // row is still the best answer we have.
            return toDto(verifications.findByUserId(userId).orElse(null));
        }
        return toDto(record(userId, verdict));
    }

    @Transactional(readOnly = true)
    IdentityVerificationDto mine(UUID userId) {
        return toDto(verifications.findByUserId(userId).orElse(null));
    }

    // MARK: The vendor's side

    /**
     * Applies one webhook delivery.
     *
     * <p>The signature was checked before this was called. What is checked here
     * is that the delivery is new, and that it belongs to someone we know: a
     * payload naming an {@code externalUserId} that isn't one of our profiles is
     * logged and dropped rather than creating a row from a stranger's claim.
     */
    @Transactional
    void applyWebhook(JsonNode body) {
        String deliveryId = deliveryId(body);
        // The insert is what claims the delivery; guard with a read first rather
        // than catching a duplicate key, since a merge on an assigned id would
        // quietly become an update instead of failing.
        if (deliveryId != null && events.existsById(deliveryId)) {
            log.debug("Sumsub webhook {} already applied", deliveryId);
            return;
        }
        SumsubVerdict verdict = SumsubVerdict.fromWebhook(body);
        UUID userId = resolveUser(body, verdict);
        if (userId == null) {
            log.warn("Sumsub webhook for an unknown applicant {} — dropped",
                verdict.applicantId());
            return;
        }
        if (deliveryId != null) {
            events.save(new ProviderEvent(deliveryId, body.path("type").asText(""),
                verdict.applicantId()));
        }
        record(userId, verdict);
    }

    /**
     * The single write path for a verdict, whichever way it arrived.
     *
     * <p>{@link IdentityVerificationRecord#apply} answers whether the status
     * actually moved, and that answer is the event's condition — so a repeated
     * {@code applicantReviewed}, or a pull that confirms what a webhook already
     * told us, publishes nothing. Anything downstream of
     * {@link IdentityVerified} (a partner's verified badge, a push) therefore
     * happens once per real transition, not once per delivery.
     */
    private IdentityVerificationRecord record(UUID userId, SumsubVerdict verdict) {
        IdentityVerificationRecord record = verifications.findByUserId(userId)
            .orElseGet(() -> verifications.save(
                new IdentityVerificationRecord(userId, verdict.levelName())));
        boolean changed = record.apply(verdict);
        if (changed) {
            log.info("Identity check for {} is now {}", userId, record.getStatus());
            if (record.getStatus() == IdentityStatus.VERIFIED) {
                publisher.publishEvent(new IdentityVerified(
                    userId, record.getLevelName(), record.getVerifiedAt()));
            }
        }
        return record;
    }

    /**
     * Which of our people this payload is about.
     *
     * <p>{@code externalUserId} is our own profile id — we chose it when the
     * access token was minted — so it is the primary join, and the applicant id
     * is the fallback for a payload that omits it. Either way the answer must
     * match a verification row we already opened: nobody reaches Sumsub without
     * first asking this backend for a token, so a payload naming someone we have
     * never started a check for describes a person who does not exist here.
     */
    private UUID resolveUser(JsonNode body, SumsubVerdict verdict) {
        String external = body.path("externalUserId").asText(null);
        if (external != null && !external.isBlank()) {
            try {
                UUID claimed = UUID.fromString(external.trim());
                if (verifications.findByUserId(claimed).isPresent()) return claimed;
            } catch (IllegalArgumentException e) {
                log.warn("Sumsub webhook carried a non-UUID externalUserId");
            }
        }
        return verdict.applicantId() == null ? null
            : verifications.findByApplicantId(verdict.applicantId())
                .map(IdentityVerificationRecord::getUserId).orElse(null);
    }

    /** Sumsub's delivery identifier. Named differently across payload versions,
     *  so both are accepted; a delivery with neither simply isn't deduped. */
    private static String deliveryId(JsonNode body) {
        for (String field : new String[] {"correlationId", "inspectionId"}) {
            String value = body.path(field).asText(null);
            if (value != null && !value.isBlank()) return value.trim();
        }
        return null;
    }

    // MARK: Mapping

    private static IdentityCheck toCheck(IdentityVerificationRecord record) {
        return new IdentityCheck(record.getStatus(), record.getReason(),
            record.rejectLabelList(), record.getVerifiedAt(), record.getUpdatedAt());
    }

    /**
     * The applicant's own view; null means they have never started.
     * {@code moderationNote} is deliberately absent — it is the reviewer's
     * internal wording, and {@code reason} is the vendor's client-facing one.
     */
    private IdentityVerificationDto toDto(IdentityVerificationRecord record) {
        if (record == null) {
            return new IdentityVerificationDto(IdentityStatus.NOT_STARTED.name(), null,
                List.of(), sumsub.enabled() ? sumsub.levelName() : "",
                sumsub.enabled(), sumsub.enabled(), null, null);
        }
        IdentityStatus status = record.getStatus();
        return new IdentityVerificationDto(status.name(), record.getReason(),
            record.rejectLabelList(), record.getLevelName(),
            sumsub.enabled(), sumsub.enabled() && status.isStartable(),
            record.getVerifiedAt(), record.getUpdatedAt());
    }
}
