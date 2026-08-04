package com.gojogo.notifications.internal;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * The message push's shape (E2EE Phase G).
 *
 * <p>Everything here fails in a place nobody watches: APNs rejects an oversized
 * payload with a 4xx the sender logs at debug, and a missing
 * {@code mutable-content} produces a notification that arrives perfectly and
 * simply never gets decrypted. Both look like "push works fine" from the server.
 */
class MessagePushPayloadTests {

    private final ObjectMapper json = new ObjectMapper();
    // The dependencies are untouched by payload building; a sender with none is
    // the smallest thing that can answer the question being asked.
    private final ApnsPushSender sender = new ApnsPushSender(null, null, null, json);

    private JsonNode payload(String cipherBody) throws Exception {
        return json.readTree(sender.messagePayload(
            "Youssef", "New message", UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID(),
            2, cipherBody));
    }

    /** Without this flag iOS never runs the extension, and the banner stays generic. */
    @Test
    void carriesMutableContentAndTheEnvelope() throws Exception {
        JsonNode root = payload("c2VhbGVk");

        assertEquals(1, root.path("aps").path("mutable-content").asInt(),
            "the extension only runs for a mutable-content push");
        assertEquals("c2VhbGVk", root.path("cipherBody").asText());
        assertEquals(2, root.path("envelopeVersion").asInt());
        assertTrue(root.hasNonNull("messageId"), "the extension addresses the message by id");
        assertTrue(root.hasNonNull("senderId"), "the session to open it with is the sender's");
        assertEquals("New message", root.path("aps").path("alert").path("body").asText(),
            "the server's own body stays generic — it cannot read the message");
    }

    /**
     * A first (PreKey) message carries an identity key, a base key and a Kyber
     * ciphertext, and can exceed what APNs will accept. The notification must
     * survive that; only the envelope is expendable, because the extension can
     * fetch the body by id.
     */
    @Test
    void dropsAnEnvelopeThatWouldNotFit() throws Exception {
        String huge = "A".repeat(5000);
        byte[] bytes = sender.messagePayload("Youssef", "New message", UUID.randomUUID(),
            UUID.randomUUID(), UUID.randomUUID(), 2, huge);
        JsonNode root = json.readTree(bytes);

        assertTrue(bytes.length <= 4096, "APNs rejects a payload over 4 KB outright");
        assertFalse(root.has("cipherBody"), "the body goes, not the notification");
        assertTrue(root.hasNonNull("messageId"), "the ids stay, so the body can be fetched");
        assertEquals(1, root.path("aps").path("mutable-content").asInt());
    }

    /** A legacy plaintext message has no envelope at all and must still push. */
    @Test
    void plaintextMessageStillPushes() throws Exception {
        byte[] bytes = sender.messagePayload("Youssef", "hey", UUID.randomUUID(),
            UUID.randomUUID(), UUID.randomUUID(), null, null);
        JsonNode root = json.readTree(bytes);

        assertFalse(root.has("cipherBody"));
        assertFalse(root.has("envelopeVersion"));
        assertEquals("hey", root.path("aps").path("alert").path("body").asText());
    }
}
