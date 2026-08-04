package com.gojogo.notifications.internal;

import com.gojogo.messaging.MessageSent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * Pushes an APNs alert to each recipient of a chat message. Messages aren't part
 * of the activity feed (they live in the conversation), so this only fires the
 * push — it doesn't persist a notification row.
 *
 * <p>Unlike the social listeners this is a plain {@link EventListener}: messaging
 * writes to DynamoDB outside any JPA transaction, so a {@code
 * TransactionalEventListener} would never fire. {@link ApnsPushSender} is
 * fire-and-forget, so the (synchronous) publish call stays cheap.
 */
@Component
class MessageNotificationListener {

    private final ApnsPushSender apns;

    MessageNotificationListener(ApnsPushSender apns) {
        this.apns = apns;
    }

    @EventListener
    void onMessage(MessageSent event) {
        String body = event.preview() != null && !event.preview().isBlank()
            ? event.preview() : "Sent you a message";
        for (UUID recipient : event.recipientIds()) {
            // Resolved per recipient: whoever privately renamed the sender sees
            // the name they chose, not the one the sender set.
            String title = event.titleFor(recipient);
            // The body stays generic for an encrypted message — it always has,
            // and it is what a device with no extension, or a locked keychain,
            // or previews turned off, will show. The envelope beside it is what
            // a device that *can* decrypt uses to replace it (E2EE Phase G).
            apns.notifyMessage(recipient, title != null ? title : "New message",
                body, event.conversationId(), event.messageId(), event.senderId(),
                event.envelopeVersion(), event.cipherBody());
        }
    }
}
