package com.gojogo.search.internal;

import com.gojogo.search.SearchKind;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

interface SearchEntryRepository extends JpaRepository<SearchEntry, UUID> {

    Optional<SearchEntry> findByKindAndRefId(SearchKind kind, UUID refId);

    /**
     * The ranking SPECS §13 asks for, in one native query: text relevance ×
     * a log-damped popularity. {@code websearch_to_tsquery} parses the user's
     * words safely — quoted phrases and dashes behave, and nothing a user
     * types can break the query.
     */
    @Query(value = """
        SELECT * FROM search.document
        WHERE active
          AND tsv @@ websearch_to_tsquery('simple', :q)
          AND (:kind IS NULL OR kind = :kind)
        ORDER BY ts_rank(tsv, websearch_to_tsquery('simple', :q))
                 * (1 + ln(1 + popularity)) DESC,
                 updated_at DESC
        LIMIT :limit
        """, nativeQuery = true)
    List<SearchEntry> search(@Param("q") String q, @Param("kind") String kind,
                             @Param("limit") int limit);

    /**
     * The trending rail: engagement earned recently, decaying with age.
     *
     * <p>This used to order by lifetime {@code popularity}, which made it a
     * leaderboard — and since nothing ever refreshed that column after a
     * document was created, in practice it ordered by {@code updated_at} and
     * the rail was "newest first" wearing a popularity label. Both remain as
     * tiebreakers beneath the score, which is what decides the order now.
     */
    @Query(value = """
        SELECT * FROM search.document
        WHERE active AND (:kind IS NULL OR kind = :kind)
        ORDER BY trend_score DESC, popularity DESC, updated_at DESC
        LIMIT :limit
        """, nativeQuery = true)
    List<SearchEntry> trending(@Param("kind") String kind, @Param("limit") int limit);

    /** The recompute's claim order: never sampled first, then stalest. */
    @Query(value = """
        SELECT * FROM search.document
        WHERE active
        ORDER BY sampled_at ASC NULLS FIRST
        LIMIT :limit
        """, nativeQuery = true)
    List<SearchEntry> dueForTrendSample(@Param("limit") int limit);
}
