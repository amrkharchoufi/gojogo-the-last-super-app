package com.gojogo.search.internal;

import com.gojogo.search.SearchIndexApi;
import com.gojogo.search.SearchKind;
import com.gojogo.search.SearchableContent;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * The write side of the index. One verb: something of some kind changed, ask
 * its {@link SearchableContent} what it looks like now, and make the index say
 * that.
 *
 * <p>{@code REQUIRES_NEW}, without exception: this is called from AFTER_COMMIT
 * listeners, and a {@code @Transactional} method called from one joins the
 * transaction that just committed and throws on its first write (the incidents
 * log's own lesson). A failed index write is logged and dropped — search
 * staleness must never take a checkout down.
 */
@Service
class SearchIndexService implements SearchIndexApi {

    private static final Logger log = LoggerFactory.getLogger(SearchIndexService.class);

    private final SearchEntryRepository entries;
    private final Map<SearchKind, SearchableContent> sources = new EnumMap<>(SearchKind.class);

    SearchIndexService(SearchEntryRepository entries, List<SearchableContent> providers) {
        this.entries = entries;
        for (SearchableContent provider : providers) {
            sources.put(provider.kind(), provider);
        }
        log.info("Search indexes {} kind(s): {}", sources.size(), sources.keySet());
    }

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void reindex(SearchKind kind, UUID refId) {
        SearchableContent source = sources.get(kind);
        if (source == null) return;
        try {
            source.render(refId).ifPresentOrElse(document -> {
                SearchEntry entry = entries.findByKindAndRefId(kind, refId)
                    .orElseGet(() -> new SearchEntry(kind, refId));
                entry.apply(document);
                entries.save(entry);
            }, () -> entries.findByKindAndRefId(kind, refId).ifPresent(entries::delete));
        } catch (Exception e) {
            log.error("Reindex of {} {} failed", kind, refId, e);
        }
    }
}
