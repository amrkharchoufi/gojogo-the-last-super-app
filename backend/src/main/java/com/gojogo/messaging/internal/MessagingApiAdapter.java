package com.gojogo.messaging.internal;

import com.gojogo.messaging.MessagingApi;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.UUID;

/**
 * Exposes the narrow slice of {@link MessagingService} other modules are allowed
 * to use. Everything the adapter calls goes through the same service the REST
 * controller does, so a conversation opened from a listing is indistinguishable
 * from one started in My World — same dedupe, same fan-out.
 */
@Component
class MessagingApiAdapter implements MessagingApi {

    private final MessagingService messaging;

    MessagingApiAdapter(MessagingService messaging) {
        this.messaging = messaging;
    }

    @Override
    public UUID openDirectConversation(UUID callerId, UUID otherId) {
        return messaging.createConversation(
            callerId, new CreateConversationRequest(List.of(otherId), null, null, null)).id();
    }
}
