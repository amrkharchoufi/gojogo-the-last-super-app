package com.gojogo.messaging;

import java.util.List;
import java.util.UUID;

/**
 * Domain event published when a message is delivered into a conversation
 * (immediately, or when a send-later message comes due). Consumed by the
 * notifications module to push an APNs alert to the recipients who aren't the
 * sender. The live WebSocket fan-out is separate — this is for devices that
 * aren't currently connected.
 *
 * <p>Since E2EE Phase G the event also carries the message's identity and its
 * envelope. The server still cannot read a word of it: {@code cipherBody} is
 * the same opaque blob it stored, and it travels so the recipient's
 * <em>device</em> can decrypt it inside a notification service extension and
 * write the banner the server has been unable to write since Phase A. When the
 * body is too large for an APNs payload the push carries only the ids and the
 * extension fetches the message itself.
 */
public record MessageSent(UUID conversationId, UUID messageId, UUID senderId, String senderName,
                          String preview, List<UUID> recipientIds,
                          java.util.Map<UUID, String> senderNameByRecipient,
                          Integer envelopeVersion, String cipherBody) {

    /**
     * A push is the one place the server renders a name <em>on a specific
     * viewer's behalf</em> — the device can't rewrite an APNs payload the way it
     * rewrites a screen. So a recipient who has privately renamed the sender gets
     * their own title here, and {@link #senderName()} is the default for everyone
     * else. Everywhere else on the wire the real name travels and the client
     * applies its own renames.
     *
     * <p>This stays true under Phase G: the extension rewrites the <em>body</em>
     * and never the title, because the alias that belongs in the title is the
     * recipient's private one and only the server holds it.
     */
    public String titleFor(UUID recipientId) {
        String alias = senderNameByRecipient == null ? null : senderNameByRecipient.get(recipientId);
        return alias != null ? alias : senderName;
    }
}
