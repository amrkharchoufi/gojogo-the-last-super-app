/**
 * Messaging module — My World private network: conversations (1:1 + group /
 * circle), messages, reactions, polls, read state, typing.
 *
 * <p>Store is a single DynamoDB table ({@code gojogo-messaging}) rather than the
 * shared Postgres, matching the write pattern (high-fanout, append-heavy chat)
 * and the extraction path in ARCHITECTURE.md §4/§8. Durable writes all happen
 * here in the monolith; real-time server->client delivery goes out over an API
 * Gateway WebSocket via the {@code @connections} management API. The WebSocket
 * connection lifecycle ($connect/$disconnect) is owned by thin Lambdas that
 * register {@code connectionId <-> userId} rows in the same table; this module
 * only reads that registry to fan out.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Messaging")
package com.gojogo.messaging;
