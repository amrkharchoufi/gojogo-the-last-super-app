package com.gojogo.config.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.IdClass;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.io.Serializable;
import java.time.OffsetDateTime;
import java.util.Objects;

/**
 * One version of one knob. The primary key is (key, effective_from), because a
 * key legitimately has several rows and only the dates tell them apart.
 *
 * <p>The Java field is {@code configKey}, not {@code key}: {@code key} is a
 * reserved word in JPQL (it is the map-key function), and a query that orders by
 * it fails to parse in a way that reads like a typo.
 *
 * <p>Read-only from the application's side — nothing here writes config. Rows
 * arrive by migration until GoJoAdmin can edit them.
 */
@Entity
@Table(name = "config", schema = "platform")
@IdClass(PlatformConfigEntry.Key.class)
class PlatformConfigEntry {

    @Id
    @Column(name = "key", nullable = false)
    private String configKey;

    @Id
    @Column(name = "effective_from", nullable = false)
    private OffsetDateTime effectiveFrom;

    @Column(name = "value", nullable = false)
    private String value;

    @Column(name = "note", nullable = false)
    private String note = "";

    protected PlatformConfigEntry() {
    }

    String getConfigKey() {
        return configKey;
    }

    String getValue() {
        return value;
    }

    OffsetDateTime getEffectiveFrom() {
        return effectiveFrom;
    }

    /** Composite id. */
    static class Key implements Serializable {

        private String configKey;
        private OffsetDateTime effectiveFrom;

        @Override
        public boolean equals(Object other) {
            if (this == other) return true;
            if (!(other instanceof Key key)) return false;
            return Objects.equals(configKey, key.configKey)
                && Objects.equals(effectiveFrom, key.effectiveFrom);
        }

        @Override
        public int hashCode() {
            return Objects.hash(configKey, effectiveFrom);
        }
    }
}
