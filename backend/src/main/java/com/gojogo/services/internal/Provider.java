package com.gojogo.services.internal;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * A provisioned service provider — what a partner {@code SERVICE_PROVIDER}
 * approval creates. The profile a customer reads: bio, public qualifications,
 * areas, languages, portfolio. The papers behind the qualifications are
 * private documents; the catalog and calendar hang off this row.
 */
@Entity
@Table(name = "provider", schema = "services")
class Provider {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "display_name", nullable = false)
    private String displayName;

    @Column(name = "logo_url")
    private String logoUrl;

    @Column(name = "bio", nullable = false)
    private String bio = "";

    @Column(name = "qualifications", nullable = false)
    private String qualifications = "";

    @Column(name = "service_areas", nullable = false)
    private String serviceAreas = "";

    @Column(name = "languages", nullable = false)
    private String languages = "";

    /** The zone the availability template reads in. */
    @Column(name = "timezone", nullable = false)
    private String timezone = "UTC";

    @Column(name = "suspended", nullable = false)
    private boolean suspended;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @OneToMany(mappedBy = "provider", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    @OrderBy("sortOrder")
    private List<ProviderMedia> portfolio = new ArrayList<>();

    protected Provider() {
    }

    Provider(UUID ownerUserId, String displayName, String logoUrl) {
        this.ownerUserId = ownerUserId;
        this.displayName = displayName;
        this.logoUrl = logoUrl;
    }

    void configure(String displayName, String logoUrl, String bio, String qualifications,
                   String serviceAreas, String languages, String timezone) {
        this.displayName = displayName;
        this.logoUrl = logoUrl;
        this.bio = bio == null ? "" : bio;
        this.qualifications = qualifications == null ? "" : qualifications;
        this.serviceAreas = serviceAreas == null ? "" : serviceAreas;
        this.languages = languages == null ? "" : languages;
        if (timezone != null && !timezone.isBlank()) {
            // A zone that doesn't parse is refused at the edge; storing it
            // would break every slot computation from then on.
            this.timezone = ZoneId.of(timezone.trim()).getId();
        }
    }

    void replacePortfolio(List<String> imageUrls) {
        portfolio.clear();
        for (int i = 0; i < imageUrls.size(); i++) {
            portfolio.add(new ProviderMedia(this, i, imageUrls.get(i)));
        }
    }

    ZoneId zone() {
        return ZoneId.of(timezone);
    }

    void setSuspended(boolean suspended) {
        this.suspended = suspended;
    }

    UUID getId() {
        return id;
    }

    UUID getOwnerUserId() {
        return ownerUserId;
    }

    String getDisplayName() {
        return displayName;
    }

    String getLogoUrl() {
        return logoUrl;
    }

    String getBio() {
        return bio;
    }

    String getQualifications() {
        return qualifications;
    }

    String getServiceAreas() {
        return serviceAreas;
    }

    String getLanguages() {
        return languages;
    }

    String getTimezone() {
        return timezone;
    }

    boolean isSuspended() {
        return suspended;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    List<ProviderMedia> getPortfolio() {
        return portfolio;
    }
}
