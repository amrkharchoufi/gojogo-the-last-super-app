package com.gojogo.media.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Bound from {@code gojogo.media.cleanup.*}. Deletion is OFF by default: the
 * sweep runs in report-only mode (logs the orphan candidates it would delete)
 * so the reference wiring can be validated against real data before any object
 * is removed. Flip {@code delete} to true once the reported set looks right.
 */
@ConfigurationProperties(prefix = "gojogo.media.cleanup")
record MediaCleanupProperties(
    Boolean enabled,
    Boolean delete,
    Long minAgeHours,
    Integer batchSize) {

    MediaCleanupProperties {
        if (enabled == null) enabled = true;
        if (delete == null) delete = false;
        if (minAgeHours == null || minAgeHours < 1) minAgeHours = 24L;
        if (batchSize == null || batchSize < 1) batchSize = 500;
    }
}
