package com.gojogo.social.internal;

import com.gojogo.messaging.ConversationGuard;
import org.springframework.stereotype.Component;

import java.util.Collection;
import java.util.Set;
import java.util.UUID;

/**
 * "You cannot start a chat with someone a block stands between" — the social
 * module's half of {@link ConversationGuard}.
 *
 * <p>The wording is deliberately symmetric and deliberately vague. Whether it
 * was you who blocked them or them who blocked you, the message is the same
 * sentence, because the second case must not be inferable: see
 * {@link BlockService}.
 */
@Component
class BlockConversationGuard implements ConversationGuard {

    private final BlockService blocks;

    BlockConversationGuard(BlockService blocks) {
        this.blocks = blocks;
    }

    @Override
    public String refuseConversation(UUID openerId, Collection<UUID> participantIds) {
        Set<UUID> hidden = blocks.hiddenFrom(openerId);
        if (hidden.isEmpty()) {
            return null;
        }
        boolean anyBlocked = participantIds.stream()
            .anyMatch(id -> id != null && !id.equals(openerId) && hidden.contains(id));
        return anyBlocked ? "You can't start a conversation with this account." : null;
    }
}
