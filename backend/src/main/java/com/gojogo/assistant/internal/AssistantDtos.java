package com.gojogo.assistant.internal;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/**
 * What {@code /v1/assistant} returns (MADELEINE.md §3).
 *
 * <p>The shapes the iOS session builds {@code MadeleineStore} against, so they
 * are conservative on purpose: a field added later is free, and one removed is
 * a client crash on a build somebody has already shipped.
 */
final class AssistantDtos {

    private AssistantDtos() {
    }

    record ConversationDto(UUID id, String title, String state, OffsetDateTime createdAt,
                           OffsetDateTime lastActiveAt) {

        static ConversationDto of(AssistantConversation conversation) {
            return new ConversationDto(conversation.getId(), conversation.getTitle(),
                conversation.getState().name(), conversation.getCreatedAt(),
                conversation.getLastActiveAt());
        }
    }

    /**
     * One ledger row as the replay view sees it.
     *
     * <p>{@code toolName} and {@code toolResultSummary} are present so the task
     * ledger (§7) and the debugging view render from the same rows the
     * conversation does — that surface costs nothing extra precisely because §3
     * already persists exactly this.
     *
     * <p>The token counters ride along for the same reason: the number that
     * decides a $9,000/month question should be visible, not buried in a table
     * somebody has to be told about.
     */
    record MessageDto(UUID id, UUID turnId, int seq, String role, String content,
                      String toolName, String toolResultSummary,
                      String model, Integer inputTokens, Integer outputTokens,
                      Integer stepCount, OffsetDateTime createdAt) {

        static MessageDto of(AssistantMessage message) {
            return new MessageDto(message.getId(), message.getTurnId(), message.getSeq(),
                message.getRole().name(), message.getContent(), message.getToolName(),
                message.getToolResultSummary(), message.getModel(), message.getInputTokens(),
                message.getOutputTokens(), message.getStepCount(), message.getCreatedAt());
        }
    }

    /**
     * A confirm card that is still live.
     *
     * <p><b>Carries no confirm token.</b> The token travels on the live socket
     * event and nowhere else (§3), so a client catching up over REST can see
     * that an approval is outstanding but cannot approve it from a replay.
     */
    record PendingActionDto(UUID id, String toolName, String summary, Long amountMinor,
                            String currency, OffsetDateTime expiresAt) {

        static PendingActionDto of(AssistantAction action) {
            return new PendingActionDto(action.getId(), action.getToolName(),
                action.getSummary(), action.getAmountMinor(), action.getCurrency(),
                action.getExpiresAt());
        }
    }

    record ConversationDetailDto(ConversationDto conversation, List<MessageDto> messages,
                                 List<PendingActionDto> pendingActions) {
    }

    /** Long enough for a paragraph, short enough that nobody pastes a book into
     *  a context window they are paying for by the token. */
    record PostMessageRequest(@NotBlank @Size(max = 4000) String text) {
    }

    /** §3: a turn is started, not awaited. */
    record TurnStartedDto(UUID turnId) {
    }
}
