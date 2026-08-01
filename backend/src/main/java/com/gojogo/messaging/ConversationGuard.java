package com.gojogo.messaging;

import java.util.Collection;
import java.util.UUID;

/**
 * A veto on starting a conversation, implemented <em>by</em> other modules and
 * called by this one.
 *
 * <p>The direction is the point. Blocking lives in {@code social}, next to the
 * follow graph it has to tear down in the same transaction — but messaging is a
 * platform capability, and a platform module reaching into a vertical to ask
 * permission would invert the layering the whole architecture rests on
 * (ARCHITECTURE §2). So the rule is handed <em>down</em>: {@code social}
 * implements this, {@code messaging} collects whatever implementations exist and
 * refuses if any of them says no. A messaging module with no guards on the
 * classpath — the extracted-service case — behaves exactly as it did before this
 * interface existed.
 *
 * <p>It guards <b>opening</b> a thread, not sending into one. An existing
 * conversation freezes rather than vanishing: a chat history is a record of
 * something that happened, and deleting it because the relationship soured is
 * not this feature's call to make.
 */
public interface ConversationGuard {

    /**
     * Whether these people may be put in a new thread together.
     *
     * <p>Called with everyone who would be in it, including the caller. A group
     * is refused if the caller cannot be with any one of them — the alternative,
     * silently dropping a participant, produces a conversation whose membership
     * nobody agreed to.
     *
     * @return null if there is no objection, otherwise a sentence the caller
     *         may show the user. It must not name <em>which</em> direction a
     *         block runs in, for the reason {@code social} explains.
     */
    String refuseConversation(UUID openerId, Collection<UUID> participantIds);
}
