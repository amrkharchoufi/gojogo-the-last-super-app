package com.gojogo.kyc.internal;

import com.fasterxml.jackson.databind.JsonNode;
import com.gojogo.kyc.IdentityStatus;

import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

/**
 * One answer from Sumsub, in the platform's own vocabulary.
 *
 * <p>The translation lives here because Sumsub says one thing with three fields
 * — {@code reviewStatus} for how far along it is, {@code reviewAnswer} for the
 * verdict, {@code reviewRejectType} for whether a refusal is final — and both
 * ways an answer reaches us (a webhook push, a pull of the applicant) carry
 * those same three, nested slightly differently. Parsing both into one shape
 * here is what keeps {@link KycService} free of vendor JSON.
 */
record SumsubVerdict(String applicantId, String levelName, IdentityStatus status,
                     String clientComment, String moderationComment,
                     List<String> rejectLabels, OffsetDateTime eventAt) {

    /** Sumsub's own timestamps, e.g. {@code 2026-07-30 09:22:28}, always UTC. */
    private static final DateTimeFormatter SUMSUB_TIME =
        DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    /**
     * A webhook body. The review fields sit at the top level here, and the
     * delivery time arrives as {@code createdAtMs}.
     */
    static SumsubVerdict fromWebhook(JsonNode body) {
        JsonNode result = body.path("reviewResult");
        return new SumsubVerdict(
            text(body, "applicantId"),
            nullToEmpty(text(body, "levelName")),
            status(text(body, "reviewStatus"), result, text(body, "type")),
            text(result, "clientComment"),
            text(result, "moderationComment"),
            labels(result),
            time(text(body, "createdAtMs")));
    }

    /**
     * A pulled applicant. Same three fields, one level down under {@code review},
     * and the applicant's own id is the document id rather than a named field.
     */
    static SumsubVerdict fromApplicant(JsonNode applicant) {
        JsonNode review = applicant.path("review");
        JsonNode result = review.path("reviewResult");
        return new SumsubVerdict(
            text(applicant, "id"),
            nullToEmpty(text(review, "levelName")),
            status(text(review, "reviewStatus"), result, null),
            text(result, "clientComment"),
            text(result, "moderationComment"),
            labels(result),
            time(text(review, "reviewDate")));
    }

    /**
     * The one piece of real interpretation.
     *
     * <p>{@code completed} is the only status that carries a verdict, and a
     * refusal splits on {@code reviewRejectType}: {@code RETRY} means the
     * documents were bad and the applicant may go round again, {@code FINAL}
     * means the answer is no. Treating those alike is the classic mistake — it
     * either strands a person with a blurry photo or invites a rejected one to
     * keep trying.
     *
     * <p>Anything unrecognised reads as {@code IN_REVIEW}, never as a verdict:
     * a status this code has not been taught is not permission to let someone
     * through, and it is not grounds to refuse them either.
     */
    private static IdentityStatus status(String reviewStatus, JsonNode result, String eventType) {
        if ("applicantReset".equals(eventType) || "applicantDeleted".equals(eventType)) {
            return IdentityStatus.NOT_STARTED;
        }
        String state = reviewStatus == null ? "" : reviewStatus.toLowerCase();
        return switch (state) {
            case "init" -> IdentityStatus.PENDING;
            case "completed" -> verdict(result);
            // pending / queued / prechecked / onhold / awaitinguser — all "not
            // your move, not yet an answer".
            default -> IdentityStatus.IN_REVIEW;
        };
    }

    private static IdentityStatus verdict(JsonNode result) {
        String answer = text(result, "reviewAnswer");
        if ("GREEN".equalsIgnoreCase(answer)) return IdentityStatus.VERIFIED;
        if ("RED".equalsIgnoreCase(answer)) {
            return "FINAL".equalsIgnoreCase(text(result, "reviewRejectType"))
                ? IdentityStatus.REJECTED
                : IdentityStatus.RESUBMISSION_REQUESTED;
        }
        return IdentityStatus.IN_REVIEW;
    }

    private static List<String> labels(JsonNode result) {
        JsonNode node = result.path("reviewRejectLabels");
        if (!node.isArray()) return List.of();
        List<String> labels = new ArrayList<>(node.size());
        node.forEach(label -> labels.add(label.asText()));
        return List.copyOf(labels);
    }

    /** Accepts epoch millis (webhooks) or Sumsub's UTC timestamp (applicants). */
    private static OffsetDateTime time(String raw) {
        if (raw == null || raw.isBlank()) return null;
        try {
            if (raw.chars().allMatch(Character::isDigit)) {
                return OffsetDateTime.ofInstant(
                    java.time.Instant.ofEpochMilli(Long.parseLong(raw)), ZoneOffset.UTC);
            }
            return LocalDateTime.parse(raw.trim(), SUMSUB_TIME).atOffset(ZoneOffset.UTC);
        } catch (RuntimeException e) {
            // A timestamp we can't read is not worth failing a verdict over; it
            // only costs us the staleness check on that one delivery.
            return null;
        }
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node.path(field);
        return value.isMissingNode() || value.isNull() ? null : value.asText();
    }

    private static String nullToEmpty(String value) {
        return value == null ? "" : value;
    }
}
