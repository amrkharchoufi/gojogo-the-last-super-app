package com.gojogo.search.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.search.SearchKind;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * The query surface (SPECS §13): {@code GET /v1/search?q=&kind=} ranked by
 * relevance × popularity, and the trending rail, cached for the CONFIG
 * refresh window because trending is an aggregate, not a live read.
 */
@RestController
class SearchController {

    private final SearchEntryRepository entries;
    private final ConfigApi config;

    /** Trending rails per kind, refreshed on the CONFIG cadence. */
    private final ConcurrentHashMap<String, CachedRail> rails = new ConcurrentHashMap<>();

    SearchController(SearchEntryRepository entries, ConfigApi config) {
        this.entries = entries;
        this.config = config;
    }

    @GetMapping("/v1/search")
    List<SearchHit> search(@AuthenticationPrincipal Jwt jwt,
                           @RequestParam String q,
                           @RequestParam(required = false) String kind,
                           @RequestParam(defaultValue = "20") int limit) {
        if (q == null || q.isBlank()) {
            return List.of();
        }
        String kindName = parseKind(kind);
        return entries.search(q.trim(), kindName, Math.clamp(limit, 1, 50)).stream()
            .map(SearchHit::of)
            .toList();
    }

    @GetMapping("/v1/search/trending")
    List<SearchHit> trending(@AuthenticationPrincipal Jwt jwt,
                             @RequestParam(required = false) String kind,
                             @RequestParam(defaultValue = "20") int limit) {
        String kindName = parseKind(kind);
        long refreshMinutes = Math.clamp(config.number("search.trending.refresh.minutes", 15),
            1, 1440);
        int size = Math.clamp(limit, 1, 50);
        String cacheKey = (kindName == null ? "ALL" : kindName) + ":" + size;
        CachedRail cached = rails.get(cacheKey);
        if (cached == null
            || cached.at().isBefore(OffsetDateTime.now().minusMinutes(refreshMinutes))) {
            cached = new CachedRail(entries.trending(kindName, size).stream()
                .map(SearchHit::of)
                .toList(), OffsetDateTime.now());
            rails.put(cacheKey, cached);
        }
        return cached.hits();
    }

    private static String parseKind(String kind) {
        if (kind == null || kind.isBlank() || kind.equalsIgnoreCase("all")) {
            return null;
        }
        try {
            return SearchKind.valueOf(kind.trim().toUpperCase()).name();
        } catch (IllegalArgumentException unknown) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Unknown kind " + kind);
        }
    }

    record SearchHit(UUID refId, String kind, String title, String snippet, String category,
                     long popularity, OffsetDateTime updatedAt) {

        static SearchHit of(SearchEntry entry) {
            String body = entry.getBody();
            return new SearchHit(entry.getRefId(), entry.getKind().name(), entry.getTitle(),
                body.length() <= 200 ? body : body.substring(0, 200) + "…",
                entry.getCategory(), entry.getPopularity(), entry.getUpdatedAt());
        }
    }

    private record CachedRail(List<SearchHit> hits, OffsetDateTime at) {
    }
}
