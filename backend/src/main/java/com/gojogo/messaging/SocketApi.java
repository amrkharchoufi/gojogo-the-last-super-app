package com.gojogo.messaging;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Server→client delivery over the WorldSocket, for modules that have something
 * live to say and no socket of their own.
 *
 * <p>Messaging owns the transport — the API Gateway WebSocket, the connection
 * registry the {@code $connect} Lambda writes, and the {@code @connections}
 * fan-out — because it was the first module to need one. Madeleine is the
 * second (MADELEINE.md §1: "the exact pattern messaging already uses. No new
 * transport"), and rather than stand up a parallel socket she borrows this one.
 *
 * <p><b>This is a pipe, not a mailbox.</b> Nothing is stored, nothing is
 * retried, and a recipient with no live connection simply misses it. Callers
 * must have already durably written whatever they are announcing, so a client
 * that reconnects can catch up over REST — messaging does exactly that with its
 * own messages, and Madeleine does it with {@code AssistantMessage} rows. A
 * caller that treats a socket event as the record of what happened has built a
 * product that forgets things when a phone goes through a tunnel.
 *
 * <p>Best-effort, and never throws: a fan-out failure must not fail the write
 * that occasioned it.
 */
public interface SocketApi {

    /**
     * Deliver one envelope to every live connection of each recipient.
     *
     * @param envelope serialised as JSON as-is. The top-level shape is the
     *                 caller's contract with its own client — messaging sends
     *                 {@code {"type": …}}, Madeleine sends MADELEINE.md §3's
     *                 {@code {"kind": "MADELEINE", …}} — so this module does
     *                 not inspect or decorate it.
     */
    void publish(List<UUID> recipientProfileIds, Map<String, Object> envelope);
}
