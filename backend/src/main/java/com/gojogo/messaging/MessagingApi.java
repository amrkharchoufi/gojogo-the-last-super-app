package com.gojogo.messaging;

import java.util.UUID;

/**
 * Public API of the messaging module. This is the only entry point other
 * modules may use — never its repositories, DTOs or the DynamoDB table.
 *
 * <p>Deliberately narrow: a vertical (economy today, delivery/travel later)
 * needs to put two people in a thread, not to drive chat. Everything past that
 * — attachments, reactions, read state — stays on the messaging REST surface
 * the client already talks to.
 */
public interface MessagingApi {

    /**
     * Opens the 1:1 conversation between two people, reusing the existing one
     * when there is one, and returns its id. The caller must be one of the two.
     */
    UUID openDirectConversation(UUID callerId, UUID otherId);
}
