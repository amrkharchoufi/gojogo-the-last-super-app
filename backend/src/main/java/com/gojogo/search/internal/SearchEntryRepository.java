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

    /** The trending rail: pure engagement order, per kind or across all. */
    @Query(value = """
        SELECT * FROM search.document
        WHERE active AND (:kind IS NULL OR kind = :kind)
        ORDER BY popularity DESC, updated_at DESC
        LIMIT :limit
        """, nativeQuery = true)
    List<SearchEntry> trending(@Param("kind") String kind, @Param("limit") int limit);
}
