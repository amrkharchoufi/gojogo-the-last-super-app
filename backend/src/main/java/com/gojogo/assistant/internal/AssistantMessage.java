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
 * One row of the ledger (MADELEINE.md §3).
 *
 * <p><b>This is a story, not a transcript.</b> The raw model context is not
 * persisted anywhere: a row holds what the user said, what Madeleine said, or
 * that a tool ran and the trimmed summary that entered context — never the
 * token stream, and never the raw tool payload. That is what makes a route or
 * model change cost at most one turn (MADELEINE-INFERENCE.md §7) and what makes
 * the task ledger a trust surface rather than a debug dump.
 *
 * <p>The token counters ride on the {@code MADELEINE} row that closes a turn.
 * They are written from the first turn this module ever runs because
 * MADELEINE-INFERENCE.md §6's switch trigger is worthless without them, and
 * because counters retrofitted into a working loop end up approximate.
 */
@Entity
@Table(name = "message", schema = "assistant")
class AssistantMessage {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "conversation_id", nullable = false)
    private UUID conversationId;

    /** Every row one user message produced shares this. The replay view and the
     *  task ledger both read by it. */
    @Column(name = "turn_id", nullable = false)
    private UUID turnId;

    @Column(name = "seq", nullable = false)
    private int seq;

    @Enumerated(EnumType.STRING)
    @Column(name = "role", nullable = false, length = 16)
    private AssistantMessageRole role;

    @Column(name = "content", nullable = false)
    private String content = "";

    @Column(name = "tool_name", length = 64)
    private String toolName;

    /** What the model asked for. Kept because "why did she search for that" is
     *  the first debugging question anyone asks. */
    @Column(name = "tool_args")
    private String toolArgs;

    @Column(name = "tool_result_summary")
    private String toolResultSummary;

    @Column(name = "model", length = 120)
    private String model;

    @Column(name = "input_tokens")
    private Integer inputTokens;

    @Column(name = "output_tokens")
    private Integer outputTokens;

    @Column(name = "step_count")
    private Integer stepCount;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    protected AssistantMessage() {
    }

    private AssistantMessage(UUID conversationId, UUID turnId, int seq,
                             AssistantMessageRole role, String content) {
        this.conversationId = conversationId;
        this.turnId = turnId;
        this.seq = seq;
        this.role = role;
        this.content = content == null ? "" : content;
    }

    static AssistantMessage user(UUID conversationId, UUID turnId, int seq, String content) {
        return new AssistantMessage(conversationId, turnId, seq, AssistantMessageRole.USER,
            content);
    }

    static AssistantMessage madeleine(UUID conversationId, UUID turnId, int seq, String content) {
        return new AssistantMessage(conversationId, turnId, seq, AssistantMessageRole.MADELEINE,
            content);
    }

    static AssistantMessage tool(UUID conversationId, UUID turnId, int seq,
                                 String toolName, String toolArgs, String resultSummary) {
        AssistantMessage message = new AssistantMessage(conversationId, turnId, seq,
            AssistantMessageRole.TOOL, "");
        message.toolName = toolName;
        message.toolArgs = toolArgs;
        message.toolResultSummary = resultSummary;
        return message;
    }

    /** Stamps what the turn cost. Called once, on the row that closes it. */
    void recordUsage(String model, int inputTokens, int outputTokens, int stepCount) {
        this.model = model;
        this.inputTokens = inputTokens;
        this.outputTokens = outputTokens;
        this.stepCount = stepCount;
    }

    UUID getId() {
        return id;
    }

    UUID getConversationId() {
        return conversationId;
    }

    UUID getTurnId() {
        return turnId;
    }

    int getSeq() {
        return seq;
    }

    AssistantMessageRole getRole() {
        return role;
    }

    String getContent() {
        return content;
    }

    String getToolName() {
        return toolName;
    }

    String getToolArgs() {
        return toolArgs;
    }

    String getToolResultSummary() {
        return toolResultSummary;
    }

    String getModel() {
        return model;
    }

    Integer getInputTokens() {
        return inputTokens;
    }

    Integer getOutputTokens() {
        return outputTokens;
    }

    Integer getStepCount() {
        return stepCount;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }
}
