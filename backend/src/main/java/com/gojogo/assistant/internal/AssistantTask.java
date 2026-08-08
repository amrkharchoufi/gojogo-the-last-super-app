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
 * The autonomy unit (MADELEINE.md §7): a finite job Madeleine runs without a
 * live socket attached.
 *
 * <p><b>The runner is M6.</b> This entity exists in M2 because the ledger, the
 * actions and the messages all reference a task, and because a schema that
 * grows a table per milestone is one nobody can read at the end. Nothing in
 * this milestone creates a row.
 *
 * <p>v1 tasks are finite jobs, never standing rules — "watch prices every day"
 * changes the risk maths and gets its own spec section before it gets a state.
 */
@Entity
@Table(name = "task", schema = "assistant")
class AssistantTask {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    /** Null for a task started outside a thread; the ledger renders it alone. */
    @Column(name = "conversation_id")
    private UUID conversationId;

    @Column(name = "goal", nullable = false)
    private String goal;

    @Enumerated(EnumType.STRING)
    @Column(name = "state", nullable = false, length = 24)
    private AssistantTaskState state = AssistantTaskState.QUEUED;

    /** The plan as the model laid it out — JSON, rendered by the ledger screen
     *  and never queried into. */
    @Column(name = "step_plan", nullable = false)
    private String stepPlan = "[]";

    /** Why it ended badly, in the words shown to the user. A background agent
     *  that fails silently is worse than none. */
    @Column(name = "failure_reason")
    private String failureReason;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "finished_at")
    private OffsetDateTime finishedAt;

    protected AssistantTask() {
    }

    AssistantTask(UUID userId, UUID conversationId, String goal) {
        this.userId = userId;
        this.conversationId = conversationId;
        this.goal = goal;
    }

    UUID getId() {
        return id;
    }

    UUID getUserId() {
        return userId;
    }

    UUID getConversationId() {
        return conversationId;
    }

    String getGoal() {
        return goal;
    }

    AssistantTaskState getState() {
        return state;
    }

    String getStepPlan() {
        return stepPlan;
    }

    String getFailureReason() {
        return failureReason;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    OffsetDateTime getFinishedAt() {
        return finishedAt;
    }
}
