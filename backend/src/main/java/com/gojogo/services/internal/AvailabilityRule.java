package com.gojogo.services.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.util.UUID;

/** One open window in the weekly template: a weekday and two wall-clock
 *  minutes, read in the provider's own timezone. */
@Entity
@Table(name = "availability_rule", schema = "services")
class AvailabilityRule {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "provider_id", nullable = false)
    private UUID providerId;

    /** ISO: 1 = Monday … 7 = Sunday. */
    @Column(name = "day_of_week", nullable = false)
    private int dayOfWeek;

    @Column(name = "start_minute", nullable = false)
    private int startMinute;

    @Column(name = "end_minute", nullable = false)
    private int endMinute;

    protected AvailabilityRule() {
    }

    AvailabilityRule(UUID providerId, int dayOfWeek, int startMinute, int endMinute) {
        this.providerId = providerId;
        this.dayOfWeek = dayOfWeek;
        this.startMinute = startMinute;
        this.endMinute = endMinute;
    }

    UUID getId() {
        return id;
    }

    UUID getProviderId() {
        return providerId;
    }

    int getDayOfWeek() {
        return dayOfWeek;
    }

    int getStartMinute() {
        return startMinute;
    }

    int getEndMinute() {
        return endMinute;
    }
}
