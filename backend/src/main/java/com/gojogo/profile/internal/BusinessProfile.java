package com.gojogo.profile.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * The business-only half of a business profile. Shares its primary key with
 * {@link UserProfile}: one row, one identity — the social half is the profile
 * itself, and this table only holds what a person has no use for.
 */
@Entity
@Table(name = "business_profile", schema = "profile")
class BusinessProfile {

    @Id
    @Column(name = "profile_id")
    private UUID profileId;

    @Column(name = "owner_profile_id", nullable = false, updatable = false)
    private UUID ownerProfileId;

    @Column(name = "contact_phone", nullable = false, length = 32)
    private String contactPhone = "";

    @Column(name = "contact_email", nullable = false, length = 160)
    private String contactEmail = "";

    @Column(name = "website_url", length = 400)
    private String websiteUrl;

    @Column(name = "address_line", nullable = false, length = 200)
    private String addressLine = "";

    @Column(nullable = false, length = 80)
    private String city = "";

    @Column(nullable = false, length = 60)
    private String country = "";

    private Double latitude;

    private Double longitude;

    @Column(name = "opening_hours")
    private String openingHours;

    @Column(nullable = false)
    private boolean verified;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt = OffsetDateTime.now();

    protected BusinessProfile() {
    }

    BusinessProfile(UUID profileId, UUID ownerProfileId) {
        this.profileId = profileId;
        this.ownerProfileId = ownerProfileId;
    }

    @PreUpdate
    void touch() {
        this.updatedAt = OffsetDateTime.now();
    }

    UUID getProfileId() { return profileId; }
    UUID getOwnerProfileId() { return ownerProfileId; }
    String getContactPhone() { return contactPhone; }
    String getContactEmail() { return contactEmail; }
    String getWebsiteUrl() { return websiteUrl; }
    String getAddressLine() { return addressLine; }
    String getCity() { return city; }
    String getCountry() { return country; }
    Double getLatitude() { return latitude; }
    Double getLongitude() { return longitude; }
    String getOpeningHours() { return openingHours; }
    boolean isVerified() { return verified; }

    void setContactPhone(String contactPhone) { this.contactPhone = orEmpty(contactPhone); }
    void setContactEmail(String contactEmail) { this.contactEmail = orEmpty(contactEmail); }
    void setWebsiteUrl(String websiteUrl) { this.websiteUrl = blankToNull(websiteUrl); }
    void setAddressLine(String addressLine) { this.addressLine = orEmpty(addressLine); }
    void setCity(String city) { this.city = orEmpty(city); }
    void setCountry(String country) { this.country = orEmpty(country); }
    void setLatitude(Double latitude) { this.latitude = latitude; }
    void setLongitude(Double longitude) { this.longitude = longitude; }
    void setOpeningHours(String openingHours) { this.openingHours = blankToNull(openingHours); }
    void setVerified(boolean verified) { this.verified = verified; }

    private static String orEmpty(String value) {
        return value == null ? "" : value.trim();
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }
}
