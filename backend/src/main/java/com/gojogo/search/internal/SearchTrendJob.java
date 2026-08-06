package com.gojogo.search.internal;

import com.gojogo.config.ConfigApi;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * The half of trending that never existed.
 *
 * <p>Engagement lives in the verticals — a like on a post, a save on a
 * listing, a rating on a service — and the index only ever heard about a
 * document when it was created or edited. Nothing carried a like into
 * {@code search.document}, and nothing recomputed it, so the popularity the
 * rail sorted by was whatever the counter read at creation: zero, for every
 * post and every listing. The rail was "newest first" with a popularity label
 * on it.
 *
 * <p>Rather than have every like reach into the index — chatty, and a write
 * amplification on the hottest path in the app — the index pulls. Each cycle
 * takes the stalest slice of documents, asks their sources what the counters
 * read now, and folds the difference into a decaying score. Engagement earned
 * since the last look is added at full weight; everything older halves on the
 * configured half-life. What surfaces is what is being engaged with lately,
 * which is what the rail has claimed to show since it shipped.
 *
 * <p>Sized by the batch, not by the table: a cycle costs at most
 * {@code search.trending.recompute.batch} renders. With more documents than
 * that, each is simply visited less often — and because the decay is computed
 * from the elapsed time carried on the row rather than from a cycle count,
 * visiting a document late changes when its score updates, not what it is.
 *
 * <p>No lock, deliberately, and it survives a second task the day the service
 * scales past one: the gain is recomputed from the baseline stored on the row
 * and written in the same statement as the score, so two schedulers racing the
 * same document both measure from the same mark and arrive at the same number.
 * The loser's write is discarded, not added — a lost sample, corrected on the
 * next visit, rather than engagement counted twice.
 */
@Component
class SearchTrendJob {

    private static final Logger log = LoggerFactory.getLogger(SearchTrendJob.class);

    private final SearchEntryRepository entries;
    private final SearchIndexService index;
    private final ConfigApi config;

    SearchTrendJob(SearchEntryRepository entries, SearchIndexService index, ConfigApi config) {
        this.entries = entries;
        this.index = index;
        this.config = config;
    }

    @Scheduled(fixedDelayString = "${gojogo.search.trend-recompute-ms:900000}",
        initialDelayString = "${gojogo.search.trend-recompute-initial-ms:120000}")
    void recompute() {
        int batch = (int) Math.clamp(config.number("search.trending.recompute.batch", 500), 1, 5000);
        // Hours on the dial, minutes in the arithmetic.
        double halfLifeMinutes =
            Math.clamp(config.number("search.trending.halflife.hours", 24), 1, 720) * 60.0;

        List<SearchEntry> due = entries.dueForTrendSample(batch);
        if (due.isEmpty()) return;

        // Read the identity out before sampling: each sample runs in its own
        // transaction, which detaches these instances.
        int sampled = 0;
        for (SearchEntry entry : due) {
            index.sampleTrend(entry.getKind(), entry.getRefId(), halfLifeMinutes);
            sampled++;
        }
        log.info("Search trend: sampled {} document(s), half-life {}h", sampled,
            (long) (halfLifeMinutes / 60));
    }
}
