package com.gojogo.messaging.internal;

import com.gojogo.messaging.SocketApi;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * {@link SocketApi} over {@link Fanout} — the same connection registry and the
 * same best-effort delivery messaging's own events go out on.
 */
@Component
class SocketApiAdapter implements SocketApi {

    private final Fanout fanout;

    SocketApiAdapter(Fanout fanout) {
        this.fanout = fanout;
    }

    @Override
    public void publish(List<UUID> recipientProfileIds, Map<String, Object> envelope) {
        if (recipientProfileIds == null || recipientProfileIds.isEmpty() || envelope == null) {
            return;
        }
        fanout.publish(recipientProfileIds, envelope);
    }
}
