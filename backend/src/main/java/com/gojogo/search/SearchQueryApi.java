package com.gojogo.search;

import java.util.List;
import java.util.UUID;

/**
 * The read side of the index, for the callers that need to <em>ask</em> rather
 * than to publish — {@link SearchIndexApi}'s counterpart.
 *
 * <p>It exists because {@code GET /v1/search} was, until now, the only way to
 * query this module, and an HTTP endpoint is not something another module may
 * call. Madeleine's {@code search_all} tool (MADELEINE.md §5) is the first
 * in-process reader; the controller and this facade run the same query, so the
 * assistant and the search screen can never disagree about what exists.
 *
 * <p>Still nothing vertical-shaped in here: a {@link Hit} is what the index
 * stored, and resolving a {@code refId} into a listing or a restaurant is the
 * caller's job through the owning module's own facade.
 */
public interface SearchQueryApi {

    /**
     * Relevance × popularity, the same ranking the query surface serves.
     *
     * @param kind  null searches every kind
     * @param limit clamped to the same 1..50 the endpoint allows
     * @return an empty list for a blank query — never null, never an exception,
     *         because a search that throws is worse than one that finds nothing
     */
    List<Hit> search(String query, SearchKind kind, int limit);

    /**
     * One row of the index. {@code snippet} is the stored body, already cut to
     * a card's worth of text — callers that trim further (Madeleine trims to
     * MADELEINE.md §4's {@code toolResultMaxItems}) shorten a string rather
     * than re-querying.
     */
    record Hit(SearchKind kind, UUID refId, String title, String snippet, String category,
               long popularity) {
    }
}
