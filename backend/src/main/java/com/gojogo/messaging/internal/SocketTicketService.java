package com.gojogo.messaging.internal;

import org.springframework.stereotype.Service;

import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;

/**
 * Mints the one-shot credential the WebSocket handshake carries.
 *
 * <p><b>Why this exists.</b> A browser or an {@code URLSessionWebSocketTask}
 * cannot put an {@code Authorization} header on a {@code wss://} handshake, so
 * whatever authenticates {@code $connect} has to travel in the query string —
 * and query strings are written verbatim into API Gateway, load-balancer and
 * CloudWatch access logs. Sending the Cognito ID token there means an hour of
 * full account access sitting in plain text in a log store, which is a much
 * wider audience than the socket itself ever had.
 *
 * <p>So the app asks for one of these first, over an ordinary authenticated
 * request where the token rides in a header and is never logged, and spends it
 * on the handshake. What lands in the log is then worth nothing: it is random,
 * it is bound to one account, it dies in {@value #TTL_SECONDS} seconds, and the
 * authorizer deletes it as it reads it, so even inside that window it works
 * exactly once.
 *
 * <p><b>It carries the Cognito subject, not the profile id.</b> The connection
 * registry and {@code Fanout} key live sockets by subject, and the ticket is
 * standing in for the ID token that used to prove it.
 */
@Service
class SocketTicketService {

    /** Long enough to cover a handshake on a bad connection, short enough that a
     *  ticket recovered from a log is almost always already dead. */
    static final int TTL_SECONDS = 30;

    /** 256 bits. A ticket is a bearer credential for its lifetime, so it is
     *  guessing-proof rather than merely unique. */
    private static final int TICKET_BYTES = 32;

    private static final SecureRandom RANDOM = new SecureRandom();
    private static final Base64.Encoder ENCODER = Base64.getUrlEncoder().withoutPadding();

    private final MessagingRepository repo;

    SocketTicketService(MessagingRepository repo) {
        this.repo = repo;
    }

    /** A ticket for this Cognito subject, already stored and ready to spend. */
    SocketTicketDto mint(String cognitoSub) {
        byte[] raw = new byte[TICKET_BYTES];
        RANDOM.nextBytes(raw);
        String ticket = ENCODER.encodeToString(raw);
        Instant expiresAt = Instant.now().plusSeconds(TTL_SECONDS);
        repo.putSocketTicket(ticket, cognitoSub, expiresAt);
        return new SocketTicketDto(ticket, TTL_SECONDS);
    }
}

/** What the app spends on the handshake, and how long it has to do it. */
record SocketTicketDto(String ticket, int expiresInSeconds) {
}
