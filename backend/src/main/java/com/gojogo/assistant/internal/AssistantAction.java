package com.gojogo.assistant.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * A side effect the model asked for and does not have (MADELEINE.md §5).
 *
 * <p>Every {@code WRITE_GATED} tool call becomes one of these instead of
 * executing. That is not a policy the loop applies — it is the only thing the
 * executor knows how to do with a gated tool, which is why the classification is
 * the security model and not a prompt instruction.
 *
 * <p><b>{@code confirmToken} is the wall.</b> It is minted here, fans out to the
 * client in the {@code action_pending} event, and comes back on
 * {@code POST /actions/{id}/approve}. It is never serialised into model context
 * — so a hostile listing that talks the model into proposing an action still
 * dead-ends at a card a person reads, because the model cannot name the token
 * that would approve it. Prompt hygiene is the first fence; this is the wall.
 *
 * <p>M2 writes {@code PENDING} rows and nothing else. Validating a token,
 * executing the underlying vertical call with an idempotency key derived from
 * {@code id}, and resuming the turn are M4's.
 */
@Entity
@Table(name = "action", schema = "assistant")
class AssistantAction {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "conversation_id", nullable = false)
    private UUID conversationId;

    /** Set when the action came out of a background task (§7). */
    @Column(name = "task_id")
    private UUID taskId;

    @Column(name = "turn_id", nullable = false)
    private UUID turnId;

    @Column(name = "tool_name", nullable = false, length = 64)
    private String toolName;

    /** The model's arguments, verbatim JSON. What executes in M4 is this, not a
     *  re-reading of the conversation. */
    @Column(name = "args", nullable = false)
    private String args = "{}";

    @Column(name = "summary", nullable = false)
    private String summary;

    /**
     * The exact amount, when money moves — computed by the owning vertical's
     * quote path, never by the model. Null when nothing is charged (publishing
     * a listing leaves the user's private space without costing anything).
     */
    @Column(name = "amount_minor")
    private Long amountMinor;

    @Column(name = "currency", length = 3)
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(name = "state", nullable = false, length = 16)
    private AssistantActionState state = AssistantActionState.PENDING;

    @Column(name = "confirm_token", nullable = false)
    private UUID confirmToken = UUID.randomUUID();

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "expires_at", nullable = false)
    private OffsetDateTime expiresAt;

    @Column(name = "decided_at")
    private OffsetDateTime decidedAt;

    protected AssistantAction() {
    }

    AssistantAction(UUID conversationId, UUID taskId, UUID turnId, String toolName, String args,
                    String summary, Long amountMinor, String currency, OffsetDateTime expiresAt) {
        this.conversationId = conversationId;
        this.taskId = taskId;
        this.turnId = turnId;
        this.toolName = toolName;
        this.args = args == null ? "{}" : args;
        this.summary = summary;
        this.amountMinor = amountMinor;
        this.currency = currency;
        this.expiresAt = expiresAt;
    }

    boolean isLive(OffsetDateTime now) {
        return state == AssistantActionState.PENDING && expiresAt.isAfter(now);
    }

    UUID getId() {
        return id;
    }

    UUID getConversationId() {
        return conversationId;
    }

    UUID getTaskId() {
        return taskId;
    }

    UUID getTurnId() {
        return turnId;
    }

    String getToolName() {
        return toolName;
    }

    String getArgs() {
        return args;
    }

    String getSummary() {
        return summary;
    }

    Long getAmountMinor() {
        return amountMinor;
    }

    String getCurrency() {
        return currency;
    }

    AssistantActionState getState() {
        return state;
    }

    UUID getConfirmToken() {
        return confirmToken;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    OffsetDateTime getExpiresAt() {
        return expiresAt;
    }

    OffsetDateTime getDecidedAt() {
        return decidedAt;
    }
}
