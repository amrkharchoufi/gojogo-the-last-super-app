/**
 * Share module — public, expiring links to one thing ({@code share} schema,
 * SPECS.md §10, ARCHITECTURE.md §10 Phase 3 M5).
 *
 * <p>A platform module holding a <strong>pointer and nothing else</strong>: a
 * kind, an id, a secret, and when it stops working. What a viewer actually sees
 * is rendered on every read by the module that owns the kind, through
 * {@link com.gojogo.share.ShareableResource}, which that module implements. So
 * the dependency runs {@code travel → share} — vertical to platform, the
 * direction ARCHITECTURE §2 requires — and this is the fourth instance of the
 * plugin shape {@code messaging.ConversationGuard},
 * {@code moderation.ModeratableContent} and {@code dispatch.WorkerEligibility}
 * already use. A kind with no implementation on the classpath is simply not
 * shareable, and a token pointing at one resolves to nothing.
 *
 * <p><strong>Storing a payload instead would have been the wrong module.</strong>
 * The whole point of sharing a trip is that the person watching sees where the
 * car is <em>now</em>. A row holding a position would show them where it was
 * when the link was made, which is not a tracking link — it is a screenshot with
 * a URL.
 *
 * <p><strong>The token is the only authentication there is.</strong> Whoever
 * holds it sees the payload, because the people a trip is shared with are
 * precisely the people who do not have accounts here. That is what makes two
 * things load-bearing: the secret is long enough that guessing one is not a way
 * to watch a stranger, and every payload is deliberately thin — a first name, a
 * plate, a position, an ETA. Never a phone number, never an address book entry,
 * never the other party's profile.
 *
 * <p>Links expire, and the expiry is generous rather than exact: a link that
 * dies at the kerb leaves somebody watching a dead page at the one moment they
 * care, so a trip's link outlives its trip by a configured grace.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Share")
package com.gojogo.share;
