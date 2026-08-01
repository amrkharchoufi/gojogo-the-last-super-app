/**
 * Moderation module — reports, the human queue that works them, and the
 * takedowns that come out of it ({@code moderation} schema, SPECS.md §10).
 *
 * <p>A platform module rather than a table per vertical: the queue a person
 * works is <em>one</em> queue, and a moderator should not have to know that a
 * reported photo and a reported listing were filed in different places. App
 * Store guideline 1.2 makes this a condition of shipping user-generated content
 * at all, which is why it is a milestone rather than a nice-to-have.
 *
 * <p><strong>The module stores a pointer, never the content.</strong> A report
 * is {@code (kind, id, reason, note)}. Everything else — what the thing is, who
 * owns it, and how to take it down — comes from the vertical that owns the kind,
 * through {@link com.gojogo.moderation.ModeratableContent}, which those verticals
 * implement. The dependency therefore runs {@code social → moderation},
 * {@code watch → moderation}, {@code economy → moderation}: vertical to
 * platform, the direction ARCHITECTURE §2 requires, and the same plugin shape
 * {@code messaging}'s {@code ConversationGuard} uses. A kind with no
 * implementation on the classpath is simply not reportable, and says so.
 *
 * <p><strong>Hide before remove.</strong> The default action is the reversible
 * one: hidden content leaves every other reader's feed but stays visible,
 * flagged, to its own author, so a moderator working at speed can be wrong
 * without being permanent. {@code REMOVE} is the door that only opens outward,
 * and {@code SUSPEND} acts on the account rather than the thing — through
 * {@link com.gojogo.auth.AccountAdminApi}, so this module never learns what
 * Cognito is.
 *
 * <p><strong>Nothing here is automatic.</strong> No heuristic hides anything, no
 * report count triggers anything, and there is no scheduled job. A takedown is a
 * person's decision, for the same reason a KYC approval is
 * ({@code partner}, 2b M6).
 */
@org.springframework.modulith.ApplicationModule(displayName = "Moderation")
package com.gojogo.moderation;
