package com.gojogo.messaging.internal;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Wire DTOs for the messaging module. Kept in one file, mirroring the social
 * module's {@code Dtos.java}. Timestamps are ISO-8601 {@link Instant}s; the iOS
 * client parses them the same way it parses feed timestamps.
 */
final class Dtos {
    private Dtos() {}
}

// ---- Requests -------------------------------------------------------------

/** Start (or fetch the existing) conversation with a set of participants. */
record CreateConversationRequest(
    @NotEmpty List<UUID> participantIds,
    String title,
    UUID circleId,
    String background) {
}

/** Send a message. {@code clientId} echoes back so the sender can de-dupe its
 *  optimistic bubble against the fan-out copy. */
record SendMessageRequest(
    @NotNull String kind,
    String text,
    List<MediaItemDto> mediaItems,
    PollDto poll,
    UUID replyToMessageId,
    UUID clientId,
    Instant scheduledAt) {
}

record ReactRequest(@NotNull String tapback) {
}

record VotePollRequest(@NotNull UUID optionId) {
}

record MarkReadRequest(@NotNull UUID lastReadMessageId) {
}

// ---- Responses ------------------------------------------------------------

record ParticipantDto(UUID id, String displayName, String handle, String avatarUrl) {
}

record MediaItemDto(String imageUrl, String videoUrl, boolean isVideo, String durationLabel) {
}

record ReplySnippetDto(UUID messageId, String authorName, String preview) {
}

record ReactionDto(UUID userId, String tapback) {
}

record PollOptionDto(UUID id, @Size(max = 120) String text, List<UUID> voters) {
}

record PollDto(String question, List<PollOptionDto> options, boolean allowsMultiple) {
}

record MessageDto(
    UUID id,
    UUID conversationId,
    UUID senderId,
    String senderName,
    String kind,
    String text,
    List<MediaItemDto> mediaItems,
    PollDto poll,
    ReplySnippetDto replyTo,
    List<ReactionDto> reactions,
    Instant createdAt,
    Instant scheduledAt,
    UUID clientId) {
}

record ConversationDto(
    UUID id,
    String type,
    String title,
    boolean isGroup,
    List<ParticipantDto> participants,
    UUID circleId,
    String background,
    String preview,
    Instant lastActivityAt,
    int unread,
    boolean pinned,
    boolean muted) {
}

record MessagesResponse(List<MessageDto> messages, Instant nextBefore) {
}
