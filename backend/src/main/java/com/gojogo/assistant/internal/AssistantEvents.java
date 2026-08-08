package com.gojogo.assistant.internal;

import com.gojogo.messaging.SocketApi;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * The server→client half of MADELEINE.md §3's wire contract.
 *
 * <p>One envelope kind, one shape, and this class is the only place that builds
 * it — because it is the contract with the iOS session building
 * {@code MadeleineStore} in parallel, and a contract with two authors is a
 * contract with none:
 *
 * <pre>{@code { "kind": "MADELEINE", "conversationId": …, "turnId": …, "event": { … } } }</pre>
 *
 * <p>Sent over the WorldSocket messaging already owns
 * ({@link com.gojogo.messaging.SocketApi}) — no new transport, exactly as §1
 * requires.
 *
 * <p><b>Socket-down degrades the same way messaging does:</b> the turn still
 * runs, the ledger rows are still written, and {@code GET /conversations/{id}}
 * on foreground catches the client up. Nothing here is the record of what
 * happened — the {@code AssistantMessage} rows are — which is why a dropped
 * event costs a repaint and never a reply. The client must never fabricate an
 * optimistic Madeleine message to fill a gap.
 */
@Component
class AssistantEvents {

    private final SocketApi socket;

    AssistantEvents(SocketApi socket) {
        this.socket = socket;
    }

    /** One line about what she is doing: "Searching restaurants…". */
    void status(UUID userId, UUID conversationId, UUID turnId, String text) {
        publish(userId, conversationId, turnId, Map.of("type", "status", "text", text));
    }

    /**
     * Assistant prose.
     *
     * <p>Arrives as one event today because {@link AssistantModelClient} requests
     * non-streaming completions (see its javadoc: exact token counts are what
     * MADELEINE-INFERENCE.md §6's trigger is owed). The event type is
     * {@code token} regardless, so the client assembles growing text the same
     * way whether that is one event or two hundred — turning streaming on later
     * changes nothing above this line.
     */
    void token(UUID userId, UUID conversationId, UUID turnId, String text) {
        publish(userId, conversationId, turnId, Map.of("type", "token", "text", text));
    }

    /**
     * A confirm card (§5).
     *
     * <p><b>This is the only place the confirm token is ever serialised.</b> It
     * travels socket → client → approve call and nowhere else — never into model
     * context, never into a ledger row the model can read, never into a log.
     */
    void actionPending(UUID userId, UUID conversationId, UUID turnId, AssistantAction action) {
        Map<String, Object> event = new LinkedHashMap<>();
        event.put("type", "action_pending");
        event.put("actionId", action.getId());
        event.put("summary", action.getSummary());
        event.put("amountMinor", action.getAmountMinor());
        event.put("currency", action.getCurrency());
        event.put("expiresAt", action.getExpiresAt().toString());
        event.put("confirmToken", action.getConfirmToken());
        publish(userId, conversationId, turnId, event);
    }

    void turnDone(UUID userId, UUID conversationId, UUID turnId) {
        publish(userId, conversationId, turnId, Map.of("type", "turn_done"));
    }

    /**
     * The turn ended badly, and says so. Never a fabricated reply: a client that
     * receives this shows a failure, because a Madeleine who invents an answer
     * when her model is unreachable is worse than one who is unavailable.
     */
    void turnError(UUID userId, UUID conversationId, UUID turnId, String message) {
        publish(userId, conversationId, turnId,
            Map.of("type", "turn_error", "message", message));
    }

    private void publish(UUID userId, UUID conversationId, UUID turnId,
                         Map<String, Object> event) {
        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("kind", "MADELEINE");
        envelope.put("conversationId", conversationId.toString());
        envelope.put("turnId", turnId.toString());
        envelope.put("event", event);
        socket.publish(List.of(userId), envelope);
    }
}
