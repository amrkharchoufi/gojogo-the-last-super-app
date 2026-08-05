package com.gojogo.search;

import java.util.UUID;

/**
 * The write side of the index, for the modules that own the content. A
 * vertical calls this — from a listener on its own events, after commit —
 * whenever one of its things changed; the search module then asks that kind's
 * {@link SearchableContent} what the thing looks like now.
 *
 * <p>This direction (vertical → platform) is what keeps the module graph
 * acyclic: search imports nothing from any vertical, exactly as
 * {@code messaging} never imports the module that implements its
 * {@code ConversationGuard}.
 */
public interface SearchIndexApi {

    /** Re-render one thing into the index: upsert if its source still knows
     *  it, drop the row if it doesn't. Never throws — a failed index write is
     *  logged and dropped, because search staleness must not break a save. */
    void reindex(SearchKind kind, UUID refId);
}
