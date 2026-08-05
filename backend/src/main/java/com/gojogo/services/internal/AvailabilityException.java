package com.gojogo.services.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.LocalDate;
import java.util.UUID;

/** A day the weekly template doesn't apply — a holiday, a closed week's days. */
@Entity
@Table(name = "availability_exception", schema = "services")
class AvailabilityException {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "provider_id", nullable = false)
    private UUID providerId;

    @Column(name = "on_date", nullable = false)
    private LocalDate onDate;

    protected AvailabilityException() {
    }

    AvailabilityException(UUID providerId, LocalDate onDate) {
        this.providerId = providerId;
        this.onDate = onDate;
    }

    UUID getId() {
        return id;
    }

    UUID getProviderId() {
        return providerId;
    }

    LocalDate getOnDate() {
        return onDate;
    }
}
