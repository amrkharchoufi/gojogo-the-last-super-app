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
 * One thread with Madeleine (MADELEINE.md §3).
 *
 * <p>{@code title} is empty until the sidekick writes one after the first
 * exchange — a blank title is a real state the list screen draws a placeholder
 * for, not a missing value to invent around.
 */
@Entity
@Table(name = "conversation", schema = "assistant")
class AssistantConversation {

    @Id
    @GeneratedValue
    private UUID id;

    /** The profile this thread belongs to. Every tool call in it runs as them. */
    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "title", nullable = false, length = 120)
    private String title = "";

    @Enumerated(EnumType.STRING)
    @Column(name = "state", nullable = false, length = 16)
    private AssistantConversationState state = AssistantConversationState.ACTIVE;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "last_active_at", nullable = false)
    private OffsetDateTime lastActiveAt = OffsetDateTime.now();

    protected AssistantConversation() {
    }

    AssistantConversation(UUID userId) {
        this.userId = userId;
    }

    void touch() {
        this.lastActiveAt = OffsetDateTime.now();
    }

    UUID getId() {
        return id;
    }

    UUID getUserId() {
        return userId;
    }

    String getTitle() {
        return title;
    }

    void setTitle(String title) {
        // Trimmed to the column rather than rejected: a title is decoration, and
        // a conversation that fails to save because the sidekick was chatty is
        // a worse outcome than a shortened title.
        String next = title == null ? "" : title.strip();
        this.title = next.length() <= 120 ? next : next.substring(0, 120);
    }

    AssistantConversationState getState() {
        return state;
    }

    void archive() {
        this.state = AssistantConversationState.ARCHIVED;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    OffsetDateTime getLastActiveAt() {
        return lastActiveAt;
    }
}
