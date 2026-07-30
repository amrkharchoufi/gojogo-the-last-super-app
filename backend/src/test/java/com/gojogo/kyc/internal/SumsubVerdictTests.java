package com.gojogo.kyc.internal;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.gojogo.kyc.IdentityStatus;
import org.junit.jupiter.api.Test;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The vendor→platform translation, which is where a KYC integration quietly goes
 * wrong: every case below is one where getting it backwards would either let an
 * unverified person through or strand a verified one.
 *
 * <p>No network. These are pure functions over payloads shaped exactly like the
 * ones Sumsub sends.
 */
class SumsubVerdictTests {

    private final ObjectMapper json = new ObjectMapper();

    private SumsubVerdict webhook(String body) throws Exception {
        return SumsubVerdict.fromWebhook(json.readTree(body));
    }

    @Test
    void greenIsVerified() throws Exception {
        assertThat(webhook("""
            {"applicantId":"a1","type":"applicantReviewed","reviewStatus":"completed",
             "levelName":"id-and-liveness","reviewResult":{"reviewAnswer":"GREEN"}}
            """).status()).isEqualTo(IdentityStatus.VERIFIED);
    }

    /** A retryable refusal must not read as a final one — the app shows a "try
     *  again" button for one and refers them to support for the other. */
    @Test
    void redRetryAsksForAnotherGo() throws Exception {
        SumsubVerdict verdict = webhook("""
            {"applicantId":"a1","type":"applicantReviewed","reviewStatus":"completed",
             "reviewResult":{"reviewAnswer":"RED","reviewRejectType":"RETRY",
                             "clientComment":"Your ID photo was blurry",
                             "moderationComment":"internal note",
                             "reviewRejectLabels":["UNSATISFACTORY_PHOTOS"]}}
            """);
        assertThat(verdict.status()).isEqualTo(IdentityStatus.RESUBMISSION_REQUESTED);
        assertThat(verdict.clientComment()).isEqualTo("Your ID photo was blurry");
        assertThat(verdict.rejectLabels()).containsExactly("UNSATISFACTORY_PHOTOS");
    }

    @Test
    void redFinalIsRejected() throws Exception {
        assertThat(webhook("""
            {"applicantId":"a1","type":"applicantReviewed","reviewStatus":"completed",
             "reviewResult":{"reviewAnswer":"RED","reviewRejectType":"FINAL"}}
            """).status()).isEqualTo(IdentityStatus.REJECTED);
    }

    /**
     * A status this code hasn't been taught is not permission to let someone
     * through — and not grounds to refuse them either. It has to land on
     * "waiting", which is the only honest reading of "we don't know yet".
     */
    @Test
    void anUnknownStatusIsNeverAVerdict() throws Exception {
        for (String status : new String[] {"onHold", "queued", "prechecked", "somethingNew"}) {
            assertThat(webhook("""
                {"applicantId":"a1","reviewStatus":"%s"}
                """.formatted(status)).status())
                .as("reviewStatus=%s", status)
                .isEqualTo(IdentityStatus.IN_REVIEW);
        }
    }

    @Test
    void aResetSendsThemBackToTheStart() throws Exception {
        assertThat(webhook("""
            {"applicantId":"a1","type":"applicantReset","reviewStatus":"init"}
            """).status()).isEqualTo(IdentityStatus.NOT_STARTED);
    }

    /** The pull path carries the same three fields one level down, under
     *  {@code review} — and it is what keeps the flow working with no webhook. */
    @Test
    void aPulledApplicantParsesTheSameWay() throws Exception {
        SumsubVerdict verdict = SumsubVerdict.fromApplicant(json.readTree("""
            {"id":"5b594ade0a975a36c9349e66","externalUserId":"whatever",
             "review":{"levelName":"id-and-liveness","reviewStatus":"completed",
                       "reviewDate":"2026-07-30 09:22:28",
                       "reviewResult":{"reviewAnswer":"GREEN"}}}
            """));
        assertThat(verdict.status()).isEqualTo(IdentityStatus.VERIFIED);
        assertThat(verdict.applicantId()).isEqualTo("5b594ade0a975a36c9349e66");
        assertThat(verdict.levelName()).isEqualTo("id-and-liveness");
        assertThat(verdict.eventAt())
            .isEqualTo(OffsetDateTime.of(2026, 7, 30, 9, 22, 28, 0, ZoneOffset.UTC));
    }

    // MARK: The record

    /**
     * Webhook deliveries are not ordered and Sumsub retries them. A late
     * {@code applicantPending} landing after {@code applicantReviewed} must not
     * un-verify someone who has already passed.
     */
    @Test
    void aStaleVerdictCannotUnverifySomeone() throws Exception {
        IdentityVerificationRecord record =
            new IdentityVerificationRecord(UUID.randomUUID(), "id-and-liveness");
        assertThat(record.apply(webhook("""
            {"applicantId":"a1","reviewStatus":"completed","createdAtMs":"2000",
             "reviewResult":{"reviewAnswer":"GREEN"}}
            """))).isTrue();
        assertThat(record.getStatus()).isEqualTo(IdentityStatus.VERIFIED);

        boolean changed = record.apply(webhook("""
            {"applicantId":"a1","reviewStatus":"pending","createdAtMs":"1000"}
            """));
        assertThat(changed).isFalse();
        assertThat(record.getStatus()).isEqualTo(IdentityStatus.VERIFIED);
    }

    /**
     * The event that flips a partner's badge and fires a push hangs off this
     * boolean, so a repeated delivery reporting the same verdict has to report
     * "nothing changed".
     */
    @Test
    void reapplyingTheSameVerdictReportsNoChange() throws Exception {
        IdentityVerificationRecord record =
            new IdentityVerificationRecord(UUID.randomUUID(), "id-and-liveness");
        String payload = """
            {"applicantId":"a1","reviewStatus":"completed","createdAtMs":"2000",
             "reviewResult":{"reviewAnswer":"GREEN"}}
            """;
        assertThat(record.apply(webhook(payload))).isTrue();
        OffsetDateTime firstPassedAt = record.getVerifiedAt();
        assertThat(record.apply(webhook(payload))).isFalse();
        // And it stays the moment they *first* passed, not the latest retry.
        assertThat(record.getVerifiedAt()).isEqualTo(firstPassedAt);
    }

    /** V21 constrains VERIFIED iff verified_at; losing verification has to clear
     *  it or the insert fails on a constraint the entity should never hit. */
    @Test
    void losingVerificationClearsTheVerifiedTime() throws Exception {
        IdentityVerificationRecord record =
            new IdentityVerificationRecord(UUID.randomUUID(), "id-and-liveness");
        record.apply(webhook("""
            {"applicantId":"a1","reviewStatus":"completed","createdAtMs":"1000",
             "reviewResult":{"reviewAnswer":"GREEN"}}
            """));
        record.apply(webhook("""
            {"applicantId":"a1","type":"applicantReset","reviewStatus":"init",
             "createdAtMs":"2000"}
            """));
        assertThat(record.getStatus()).isEqualTo(IdentityStatus.NOT_STARTED);
        assertThat(record.getVerifiedAt()).isNull();
    }
}
