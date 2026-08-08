/**
 * Assistant module — Madeleine, the agentic assistant (MADELEINE.md).
 *
 * <p>A platform capability rather than a vertical: she owns no product surface
 * of her own and sells nothing. What she owns is a conversation, a loop, and a
 * registry of tools; everything she can actually <em>do</em> belongs to somebody
 * else's module and is reached through that module's public {@code *Api} facade,
 * never its repositories — the same rule every other module lives under. Where a
 * facade lacked a verb she needed, the verb was added to the facade and the
 * vertical stayed the owner of its rules. Six were added for M2:
 * {@link com.gojogo.search.SearchQueryApi},
 * {@link com.gojogo.delivery.DeliveryCatalogApi},
 * {@link com.gojogo.travel.TravelApi},
 * {@link com.gojogo.economy.MarketplaceApi},
 * {@link com.gojogo.services.BookingDirectoryApi} and
 * {@link com.gojogo.messaging.SocketApi}.
 *
 * <p><b>She acts with the caller's own identity, never an elevated service
 * account</b> (locked decision #1). Every facade call carries the signed-in
 * user's profile id, so a tool can reach exactly what its user could reach by
 * tapping — full reach, zero elevation. There is no place in this module where
 * a privilege could be borrowed, because there is no privilege to borrow.
 *
 * <p><b>The class of a tool is the security model</b> (§5). {@code READ} tools
 * execute immediately. {@code WRITE_GATED} tools are unreachable from model
 * output <em>by construction</em>: the executor consults the registry, sees the
 * class, and writes an {@code AssistantAction} carrying a confirm token the
 * model is never shown. No prompt, no argument and no autonomy setting can
 * cross that line, because the crossing is not implemented. M4 builds the
 * approval flow on top of it; this milestone builds the wall.
 *
 * <p><b>Nothing outside {@code AssistantModelClient} knows where the model
 * runs</b> (MADELEINE-INFERENCE.md §5 rule 1). The loop, the registry and the
 * executor speak OpenAI-compatible chat completions and nothing else, so the
 * route is an environment variable rather than a rewrite.
 *
 * <p><b>GojoMessages content never enters model context.</b> There is no
 * {@code read_thread} tool and no {@code send_message} tool, and there will not
 * be one — DM content is its own sealed system (the story-replies-stay-in-social
 * rule, extended). This module depends on {@code messaging} for one thing only:
 * the socket it borrows to talk to the phone.
 *
 * <p>Everything here is prefixed {@code Assistant*} per the unique-class-names
 * rule — two modules sharing a simple class name collide on both the Spring bean
 * name and Hibernate's entity name.
 *
 * <p>Scope as built (M2): the loop, the READ tools, the registry wall, and token
 * instrumentation. Gated <em>execution</em> is M4, pilot mode M5, the task
 * runner M6.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Assistant")
package com.gojogo.assistant;
