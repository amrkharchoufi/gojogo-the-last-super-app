package com.gojogo.assistant.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.UUID;
import java.util.concurrent.ExecutorService;

/**
 * Names a conversation once, from its first message, with the sidekick
 * (MADELEINE.md §2, §3).
 *
 * <p>Off the turn's critical path entirely: it runs on the tool pool while the
 * brain is already thinking, and if it fails the title simply stays empty —
 * which the list screen already draws a placeholder for. A conversation that
 * refuses to start because a decorative string could not be generated would be
 * an absurd trade.
 *
 * <p>The sidekick is handed no tools, which is how §2's "never plans, never
 * calls write tools" is enforced: not as an instruction it could ignore, but as
 * a catalog it was never given.
 */
@Component
class AssistantTitler {

    private static final Logger log = LoggerFactory.getLogger(AssistantTitler.class);

    private final AssistantConversationRepository conversations;
    private final AssistantModelClient models;
    private final AssistantPolicy policy;
    private final ExecutorService pool;

    AssistantTitler(AssistantConversationRepository conversations, AssistantModelClient models,
                    AssistantPolicy policy, ExecutorService assistantToolPool) {
        this.conversations = conversations;
        this.models = models;
        this.policy = policy;
        this.pool = assistantToolPool;
    }

    void titleIfUnnamed(UUID conversationId, String firstMessage) {
        if (!policy.titlesEnabled()) {
            return;
        }
        pool.execute(() -> {
            try {
                write(conversationId, firstMessage);
            } catch (RuntimeException e) {
                log.debug("Madeleine could not title conversation {}: {}", conversationId,
                    e.toString());
            }
        });
    }

    /**
     * No {@code @Transactional} here, and that is the point: this method is
     * invoked from a lambda on {@code this}, where a proxy-based annotation
     * would be silently inert. The model call must not sit inside a transaction
     * anyway — it takes the better part of a second and would pin a connection
     * for all of it. So the read and the write are each their own short
     * transaction, opened by the repository, with a network call in between.
     */
    private void write(UUID conversationId, String firstMessage) {
        if (conversations.findById(conversationId)
            .filter(conversation -> conversation.getTitle().isBlank())
            .isEmpty()) {
            return;
        }
        AssistantChatResult result = models.chat(AssistantModelRole.SIDEKICK,
            List.of(AssistantChatMessage.system(AssistantPrompts.TITLE),
                AssistantChatMessage.user(firstMessage)),
            List.of(), null);
        if (result.content() == null || result.content().isBlank()) {
            return;
        }
        // Re-read: the title may have been written while the model was thinking,
        // and the first one to land wins rather than the last.
        conversations.findById(conversationId)
            .filter(conversation -> conversation.getTitle().isBlank())
            .ifPresent(conversation -> {
                conversation.setTitle(result.content());
                conversations.save(conversation);
            });
    }
}
