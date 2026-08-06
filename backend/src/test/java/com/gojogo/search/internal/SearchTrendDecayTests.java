package com.gojogo.search.internal;

import com.gojogo.search.SearchKind;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.OffsetDateTime;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

/**
 * The arithmetic behind "Trending now".
 *
 * <p>It ordered by lifetime {@code popularity} with no time term, over a column
 * written only when a document was created or edited — and since nothing
 * reindexed on a like, a save or a rating, and no job recomputed it, every post
 * and every listing sat at the count it had at creation, which is zero. The
 * rail was "newest first" with a popularity label on it, and it looked
 * plausible enough that nothing caught it.
 *
 * <p>These are pure-arithmetic tests on {@link SearchEntry#sample}: there is no
 * Postgres on the machine this is built from, so the query that consumes the
 * score is covered by the schema-check boot in CI, and the score itself is
 * covered here.
 */
class SearchTrendDecayTests {

    private static final double HALF_LIFE_MINUTES = 24 * 60;

    private SearchEntry entry() {
        return new SearchEntry(SearchKind.POST, UUID.randomUUID());
    }

    @Test
    @DisplayName("the first sample sets a baseline and scores nothing")
    void firstSampleIsBaselineOnly() {
        SearchEntry entry = entry();
        OffsetDateTime now = OffsetDateTime.now();

        // A year-old post with 500 lifetime likes, seen for the first time.
        entry.sample(500, now, HALF_LIFE_MINUTES);

        // Crediting that as engagement earned right now would open the rail
        // with a spike of all-time winners — the exact behaviour being removed.
        assertThat(entry.getTrendScore()).isZero();
        assertThat(entry.getSampledPopularity()).isEqualTo(500);
        assertThat(entry.getPopularity()).isEqualTo(500);
        assertThat(entry.getSampledAt()).isEqualTo(now);
    }

    @Test
    @DisplayName("the second sample scores only what was gained since the first")
    void scoresTheGainNotTheTotal() {
        SearchEntry entry = entry();
        OffsetDateTime start = OffsetDateTime.now();
        entry.sample(500, start, HALF_LIFE_MINUTES);

        entry.sample(510, start.plusMinutes(15), HALF_LIFE_MINUTES);

        // Ten new likes, not five hundred and ten.
        assertThat(entry.getTrendScore()).isCloseTo(10, within(0.001));
    }

    @Test
    @DisplayName("a quiet document halves over one half-life")
    void decaysOnTheHalfLife() {
        SearchEntry entry = entry();
        OffsetDateTime start = OffsetDateTime.now();
        entry.sample(0, start, HALF_LIFE_MINUTES);
        entry.sample(80, start.plusMinutes(15), HALF_LIFE_MINUTES);
        assertThat(entry.getTrendScore()).isCloseTo(80, within(0.001));

        // A full half-life later with nothing gained.
        entry.sample(80, start.plusMinutes(15).plusMinutes((long) HALF_LIFE_MINUTES),
            HALF_LIFE_MINUTES);

        assertThat(entry.getTrendScore()).isCloseTo(40, within(0.001));
    }

    @Test
    @DisplayName("decay follows elapsed time, not the number of cycles that ran")
    void decayIsWallClockNotCycleCount() {
        OffsetDateTime start = OffsetDateTime.now();

        SearchEntry punctual = entry();
        punctual.sample(0, start, HALF_LIFE_MINUTES);
        punctual.sample(100, start.plusMinutes(15), HALF_LIFE_MINUTES);

        SearchEntry delayed = entry();
        delayed.sample(0, start, HALF_LIFE_MINUTES);
        delayed.sample(100, start.plusMinutes(15), HALF_LIFE_MINUTES);

        // One is visited twice over two half-lives, the other once. A missed,
        // late or restarted cycle must not change where a document lands.
        OffsetDateTime end = start.plusMinutes(15).plusMinutes((long) HALF_LIFE_MINUTES * 2);
        punctual.sample(100, start.plusMinutes(15).plusMinutes((long) HALF_LIFE_MINUTES),
            HALF_LIFE_MINUTES);
        punctual.sample(100, end, HALF_LIFE_MINUTES);
        delayed.sample(100, end, HALF_LIFE_MINUTES);

        assertThat(punctual.getTrendScore()).isCloseTo(25, within(0.001));
        assertThat(delayed.getTrendScore()).isCloseTo(punctual.getTrendScore(), within(0.001));
    }

    @Test
    @DisplayName("a counter that falls contributes zero, never a negative")
    void unlikesDoNotScoreBelowZero() {
        SearchEntry entry = entry();
        OffsetDateTime start = OffsetDateTime.now();
        entry.sample(100, start, HALF_LIFE_MINUTES);

        // Thirty people unliked it.
        entry.sample(70, start.plusMinutes(15), HALF_LIFE_MINUTES);

        // Ranking it below a thing nobody has touched at all would be worse
        // than ranking it level with one.
        assertThat(entry.getTrendScore()).isZero();
        // The baseline still follows the counter down, so a later recovery
        // scores the recovery rather than re-scoring ground already lost.
        assertThat(entry.getSampledPopularity()).isEqualTo(70);

        entry.sample(75, start.plusMinutes(30), HALF_LIFE_MINUTES);
        assertThat(entry.getTrendScore()).isCloseTo(5, within(0.001));
    }

    @Test
    @DisplayName("recent engagement outranks a bigger lifetime count")
    void recentBeatsLifetime() {
        OffsetDateTime start = OffsetDateTime.now();

        // The old winner: 10,000 likes, none of them lately.
        SearchEntry veteran = entry();
        veteran.sample(10_000, start, HALF_LIFE_MINUTES);
        veteran.sample(10_000, start.plusMinutes(15), HALF_LIFE_MINUTES);

        // Today's: 40 likes, all of them in the last quarter hour.
        SearchEntry rising = entry();
        rising.sample(0, start, HALF_LIFE_MINUTES);
        rising.sample(40, start.plusMinutes(15), HALF_LIFE_MINUTES);

        assertThat(rising.getTrendScore()).isGreaterThan(veteran.getTrendScore());
        // And the thing it is beating is still the more popular thing overall,
        // which is why popularity stays on as the tiebreaker beneath the score.
        assertThat(veteran.getPopularity()).isGreaterThan(rising.getPopularity());
    }

    @Test
    @DisplayName("a hidden or sold document stops ranking")
    void deactivateClearsTheScore() {
        SearchEntry entry = entry();
        OffsetDateTime start = OffsetDateTime.now();
        entry.sample(0, start, HALF_LIFE_MINUTES);
        entry.sample(90, start.plusMinutes(15), HALF_LIFE_MINUTES);

        entry.deactivate();

        assertThat(entry.isActive()).isFalse();
        assertThat(entry.getTrendScore()).isZero();
    }

    @Test
    @DisplayName("sampling never restamps updated_at")
    void samplingIsNotAnEdit() {
        SearchEntry entry = entry();
        OffsetDateTime before = entry.getUpdatedAt();
        OffsetDateTime start = OffsetDateTime.now().plusHours(1);

        entry.sample(10, start, HALF_LIFE_MINUTES);
        entry.sample(20, start.plusMinutes(15), HALF_LIFE_MINUTES);

        // updated_at means "the thing itself changed" and is the rail's last
        // tiebreaker. A recompute every quarter hour that stamped it would
        // make every document look permanently freshly edited.
        assertThat(entry.getUpdatedAt()).isEqualTo(before);
    }
}
