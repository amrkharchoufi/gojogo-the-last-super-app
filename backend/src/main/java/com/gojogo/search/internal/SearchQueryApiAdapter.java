package com.gojogo.search.internal;

import com.gojogo.search.SearchKind;
import com.gojogo.search.SearchQueryApi;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * {@link SearchQueryApi} over the same repository query {@code SearchController}
 * serves, so the in-process reader and the HTTP one rank identically.
 */
@Component
class SearchQueryApiAdapter implements SearchQueryApi {

    private final SearchEntryRepository entries;

    SearchQueryApiAdapter(SearchEntryRepository entries) {
        this.entries = entries;
    }

    @Override
    @Transactional(readOnly = true)
    public List<Hit> search(String query, SearchKind kind, int limit) {
        if (query == null || query.isBlank()) {
            return List.of();
        }
        return entries.search(query.trim(), kind == null ? null : kind.name(),
                Math.clamp(limit, 1, 50)).stream()
            .map(SearchQueryApiAdapter::toHit)
            .toList();
    }

    private static Hit toHit(SearchEntry entry) {
        String body = entry.getBody();
        return new Hit(entry.getKind(), entry.getRefId(), entry.getTitle(),
            body.length() <= 200 ? body : body.substring(0, 200) + "…",
            entry.getCategory(), entry.getPopularity());
    }
}
