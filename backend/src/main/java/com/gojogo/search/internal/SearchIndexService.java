package com.gojogo.search.internal;

import com.gojogo.search.SearchIndexApi;
import com.gojogo.search.SearchKind;
import com.gojogo.search.SearchableContent;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.EnumMap;
import java.util.Map;
import java.util.UUID;

/**
 * The write side of the index. One verb: something of some kind changed, ask
 * its {@link SearchableContent} what it looks like now, and make the index say
 * that.
 *
 * <p>The sources are resolved <em>lazily</em>, not in the constructor, and that
 * is load-bearing: every {@code SearchableContent} bean injects
 * {@link SearchIndexApi} — this bean — to push its module's events, so eager
 * injection here is a constructor cycle that refuses to boot. The module graph
 * is acyclic (ModularityTests proves that much); the bean graph needs this one
 * indirection on top. Found by the schema-check boot in CI, not by any unit
 * test — the same lesson as every "a path nothing has executed" entry.
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
    private final ObjectProvider<SearchableContent> providers;
    private volatile Map<SearchKind, SearchableContent> sources;

    SearchIndexService(SearchEntryRepository entries,
                       ObjectProvider<SearchableContent> providers) {
        this.entries = entries;
        this.providers = providers;
    }

    private Map<SearchKind, SearchableContent> sources() {
        Map<SearchKind, SearchableContent> resolved = sources;
        if (resolved == null) {
            resolved = new EnumMap<>(SearchKind.class);
            for (SearchableContent provider : providers) {
                resolved.put(provider.kind(), provider);
            }
            log.info("Search indexes {} kind(s): {}", resolved.size(), resolved.keySet());
            sources = resolved;
        }
        return resolved;
    }

    /**
     * Re-reads one document's live engagement and folds it into the decaying
     * trend score. Called by {@link SearchTrendJob}, never by a vertical.
     *
     * <p>{@code REQUIRES_NEW} per document rather than one transaction for the
     * batch: a source that throws should cost its own row and nothing else,
     * and a batch-wide transaction marked rollback-only by one bad render
     * would silently discard every sample taken before it.
     *
     * <p>A kind with no registered source is skipped, not deactivated. The
     * sources map is built from whatever beans exist, so "nothing answers for
     * PRODUCT" means the module didn't load — deleting its rows on that basis
     * would empty the index over a deploy ordering accident.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void sampleTrend(SearchKind kind, UUID refId, double halfLifeMinutes) {
        SearchableContent source = sources().get(kind);
        if (source == null) return;
        try {
            SearchEntry entry = entries.findByKindAndRefId(kind, refId).orElse(null);
            if (entry == null) return;
            source.render(refId).ifPresentOrElse(document -> {
                if (document.active()) {
                    entry.sample(document.popularity(), OffsetDateTime.now(), halfLifeMinutes);
                } else {
                    entry.deactivate();
                }
                entries.save(entry);
            }, () -> entries.delete(entry));
        } catch (Exception e) {
            log.error("Trend sample of {} {} failed", kind, refId, e);
        }
    }

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void reindex(SearchKind kind, UUID refId) {
        SearchableContent source = sources().get(kind);
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
