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

/** Privately rename a contact. A null or blank alias clears the rename. */
record SetContactAliasRequest(@Size(max = 60) String alias) {
}

// ---- Responses ------------------------------------------------------------

record ParticipantDto(UUID id, String displayName, String handle, String avatarUrl) {
}

record MediaItemDto(String imageUrl, String videoUrl, boolean isVideo, String durationLabel) {
}

/** {@code authorId} is what lets a client apply the viewer's private rename to a
 *  quoted reply. {@code authorName} is stored with the message and is the same
 *  string for every viewer, so it is only ever the fallback. Snippets written
 *  before this field existed decode it as null and keep rendering the name. */
record ReplySnippetDto(UUID messageId, UUID authorId, String authorName, String preview) {
}

/** One private rename, as the viewer who made it sees it. */
record ContactAliasDto(UUID contactId, String alias) {
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
    boolean muted,
    com.gojogo.messaging.ConversationContext context) {
}

record MessagesResponse(List<MessageDto> messages, Instant nextBefore, UUID peerReadMessageId) {
}
