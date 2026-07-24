package com.gojogo.messaging;

import java.util.List;
import java.util.UUID;

/**
 * Domain event published when a message is delivered into a conversation
 * (immediately, or when a send-later message comes due). Consumed by the
 * notifications module to push an APNs alert to the recipients who aren't the
 * sender. The live WebSocket fan-out is separate — this is for devices that
 * aren't currently connected.
 */
public record MessageSent(UUID conversationId, UUID senderId, String senderName,
                          String preview, List<UUID> recipientIds) {
}
