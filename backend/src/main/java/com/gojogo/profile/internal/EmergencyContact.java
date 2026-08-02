package com.gojogo.profile.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * One person to tell. See V33.
 *
 * <p><strong>The phone number is the required half and the linked profile is the
 * bonus</strong>, which is the opposite of what an app-centric design would do.
 * The person you would call in an emergency is usually not a user of the app you
 * happen to be sitting in, so a contact list that only held GojoGo accounts
 * would be empty for almost everybody at the moment it mattered.
 */
@Entity
@Table(name = "emergency_contact", schema = "profile")
class EmergencyContact {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "profile_id", nullable = false, updatable = false)
    private UUID profileId;

    @Column(nullable = false, length = 80)
    private String name = "";

    @Column(nullable = false, length = 32)
    private String phone = "";

    @Column(nullable = false, length = 40)
    private String relationship = "";

    @Column(name = "linked_profile_id")
    private UUID linkedProfileId;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    protected EmergencyContact() {
    }

    EmergencyContact(UUID profileId, int sortOrder) {
        this.profileId = profileId;
        this.sortOrder = sortOrder;
        this.createdAt = OffsetDateTime.now();
    }

    void apply(String name, String phone, String relationship, UUID linkedProfileId) {
        this.name = trim(name, 80);
        this.phone = trim(phone, 32);
        this.relationship = trim(relationship, 40);
        this.linkedProfileId = linkedProfileId;
    }

    void setSortOrder(int value) {
        this.sortOrder = value;
    }

    private static String trim(String value, int max) {
        if (value == null) return "";
        String trimmed = value.trim();
        return trimmed.length() <= max ? trimmed : trimmed.substring(0, max);
    }

    UUID getId() { return id; }
    UUID getProfileId() { return profileId; }
    String getName() { return name; }
    String getPhone() { return phone; }
    String getRelationship() { return relationship; }
    UUID getLinkedProfileId() { return linkedProfileId; }
    int getSortOrder() { return sortOrder; }
}
