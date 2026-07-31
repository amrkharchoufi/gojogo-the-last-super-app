package com.gojogo.config.internal;

import com.gojogo.config.ConfigApi;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Reads {@code platform.config}, and reads it rarely.
 *
 * <p>The whole table is loaded in one query and kept for {@value #CACHE_TTL_MS}
 * milliseconds (SPECS.md §14). Per-key caching would be worse in both
 * directions: more queries when a checkout reads six knobs, and a longer window
 * in which two knobs a caller compares against each other come from different
 * points in time. One snapshot, one age.
 *
 * <p>A refresh that fails keeps serving the previous snapshot. The registry
 * holds policy, not correctness — an unreachable database is already a much
 * larger problem, and a fee that is 60 seconds stale is not one at all.
 */
@Service
class ConfigService implements ConfigApi {

    private static final Logger log = LoggerFactory.getLogger(ConfigService.class);

    private static final long CACHE_TTL_MS = 60_000L;
    private static final Set<String> TRUTHY = Set.of("true", "yes", "on", "1");

    private final ConfigRepository repository;

    /** Snapshot + the moment it was taken, swapped as one so a reader never
     *  sees a half-refreshed map. */
    private final AtomicReference<Snapshot> snapshot =
        new AtomicReference<>(new Snapshot(Map.of(), 0L));

    ConfigService(ConfigRepository repository) {
        this.repository = repository;
    }

    @Override
    public String string(String key, String defaultValue) {
        String value = current().get(key);
        return value == null || value.isBlank() ? defaultValue : value;
    }

    @Override
    public long number(String key, long defaultValue) {
        String value = string(key, null);
        if (value == null) return defaultValue;
        try {
            return Long.parseLong(value.trim());
        } catch (NumberFormatException e) {
            // A typo in a policy row must not become a zero fee or a zero
            // limit. Fall back to the caller's default, loudly.
            log.warn("Config key '{}' is not a number ('{}') — using {}", key, value, defaultValue);
            return defaultValue;
        }
    }

    @Override
    public boolean flag(String key, boolean defaultValue) {
        String value = string(key, null);
        return value == null ? defaultValue : TRUTHY.contains(value.trim().toLowerCase());
    }

    private Map<String, String> current() {
        Snapshot held = snapshot.get();
        if (System.currentTimeMillis() - held.loadedAt() < CACHE_TTL_MS) {
            return held.values();
        }
        return reload(held).values();
    }

    @Transactional(readOnly = true)
    Snapshot reload(Snapshot stale) {
        try {
            // Ascending by effective date, so the newest version of a key is
            // the last one written into the map.
            List<PlatformConfigEntry> rows = repository.effectiveNow();
            Map<String, String> values = new HashMap<>();
            for (PlatformConfigEntry row : rows) {
                values.put(row.getConfigKey(), row.getValue());
            }
            Snapshot fresh = new Snapshot(Map.copyOf(values), System.currentTimeMillis());
            snapshot.set(fresh);
            return fresh;
        } catch (RuntimeException e) {
            log.warn("Could not refresh platform config — serving the previous snapshot: {}",
                e.toString());
            // Push the clock forward so a database that is down doesn't turn
            // every config read into a failing query.
            Snapshot retained = new Snapshot(stale.values(), System.currentTimeMillis());
            snapshot.set(retained);
            return retained;
        }
    }

    record Snapshot(Map<String, String> values, long loadedAt) {
    }
}
