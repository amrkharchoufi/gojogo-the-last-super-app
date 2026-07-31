package com.gojogo.config.internal;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;

interface ConfigRepository extends JpaRepository<PlatformConfigEntry, PlatformConfigEntry.Key> {

    /**
     * Every knob that has taken effect, oldest version first.
     *
     * <p>Ascending order is load-bearing: the caller builds the snapshot by
     * putting rows into a map in this order, so the newest effective row for a
     * key naturally overwrites the older ones. That is cheaper and far easier to
     * read than a window function, and the table is tens of rows.
     */
    @Query("""
        select c from PlatformConfigEntry c
        where c.effectiveFrom <= CURRENT_TIMESTAMP
        order by c.configKey asc, c.effectiveFrom asc
        """)
    List<PlatformConfigEntry> effectiveNow();
}
