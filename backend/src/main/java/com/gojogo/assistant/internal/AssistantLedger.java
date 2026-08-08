package com.gojogo.assistant.internal;

import com.gojogo.assistant.internal.AssistantToolExecutor.AssistantToolOutcome;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Reads and writes the {@code AssistantMessage} rows that are the story of a
 * conversation (MADELEINE.md §3).
 *
 * <p>Separate from {@link AssistantTurnRunner} for one reason that matters:
 * every write here is its own transaction. The loop runs on a pool thread across
 * many seconds and several network calls, and holding a database transaction
 * open across all of it would pin a connection for the length of a model round
 * trip. Each row is committed as it is written, which is also what makes the
 * ledger true if the process dies mid-turn — the steps that happened stay
 * recorded.
 *
 * <p>{@code REQUIRES_NEW} rather than the default: these methods are also
 * reachable from callers that already hold a transaction, and this codebase has
 * been bitten before by a write joining a transaction it had no business
 * joining.
 */
@Component
class AssistantLedger {

    private final AssistantMessageRepository messages;
    private final AssistantActionRepository actions;
    private final AssistantConversationRepository conversations;

    AssistantLedger(AssistantMessageRepository messages, AssistantActionRepository actions,
                    AssistantConversationRepository conversations) {
        this.messages = messages;
        this.actions = actions;
        this.conversations = conversations;
    }

    /**
     * The conversation replayed as prose, oldest first.
     *
     * <p>{@code USER} and {@code MADELEINE} rows only. A finished turn's tool
     * calls are ledger, not context: the model already saw their results when it
     * used them, and re-feeding the mechanics of every past turn is how a cheap
     * conversation becomes an expensive one.
     */
    @Transactional(readOnly = true)
    List<AssistantChatMessage> tail(UUID conversationId, int limit) {
        List<AssistantMessage> rows = messages.findByConversationIdOrderBySeqDesc(
            conversationId, PageRequest.of(0, limit));
        List<AssistantChatMessage> tail = new ArrayList<>(rows.size());
        for (int i = rows.size() - 1; i >= 0; i--) {
            AssistantMessage row = rows.get(i);
            switch (row.getRole()) {
                case USER -> tail.add(AssistantChatMessage.user(row.getContent()));
                case MADELEINE -> tail.add(AssistantChatMessage.assistant(row.getContent()));
                case TOOL -> {
                    // Deliberately dropped; see the method javadoc.
                }
            }
        }
        return tail;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    AssistantMessage recordUserMessage(UUID conversationId, UUID turnId, String text) {
        AssistantMessage row = messages.save(AssistantMessage.user(conversationId, turnId,
            nextSeq(conversationId), text));
        conversations.findById(conversationId).ifPresent(AssistantConversation::touch);
        return row;
    }

    /**
     * That a tool ran, and the trimmed summary that entered context — never the
     * raw payload, and never the {@code <user_content>} wrapper, which is
     * plumbing rather than part of the story.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void recordToolCall(UUID conversationId, UUID turnId, AssistantToolOutcome outcome) {
        messages.save(AssistantMessage.tool(conversationId, turnId, nextSeq(conversationId),
            outcome.call().name(), outcome.call().arguments(), outcome.ledgerSummary()));
    }

    /** The row that closes a turn, carrying what the turn cost. */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void recordReply(UUID conversationId, UUID turnId, String text, String model,
                     int inputTokens, int outputTokens, int steps) {
        AssistantMessage row = AssistantMessage.madeleine(conversationId, turnId,
            nextSeq(conversationId), text);
        row.recordUsage(model, inputTokens, outputTokens, steps);
        messages.save(row);
        conversations.findById(conversationId).ifPresent(AssistantConversation::touch);
    }

    @Transactional(readOnly = true)
    Optional<AssistantAction> pendingAction(UUID actionId) {
        return actions.findById(actionId);
    }

    /**
     * The next sequence number in this conversation.
     *
     * <p>Read-then-write, and safe here because {@code concurrentTurnsPerUser=1}
     * means one writer per conversation at a time. The unique constraint on
     * {@code (conversation_id, seq)} is the backstop if that ever stops being
     * true — a violation is loud, which is what it should be.
     */
    private int nextSeq(UUID conversationId) {
        return messages.highestSeq(conversationId) + 1;
    }
}
