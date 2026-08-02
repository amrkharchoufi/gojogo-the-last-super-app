package com.gojogo.partner.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * One business's application to work on the platform. There is at most one per
 * person per {@link PartnerKind} — a rejected application is repaired and
 * resubmitted rather than replaced, so its documents and the reviewer's note
 * survive the fix.
 */
@Entity
@Table(name = "partner_account", schema = "partner")
class PartnerAccount {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "user_id", nullable = false, updatable = false)
    private UUID userId;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, updatable = false)
    private PartnerKind kind;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private PartnerStatus status = PartnerStatus.DRAFT;

    @Column(name = "business_name", nullable = false)
    private String businessName;

    /** The public identity this application commerce-enables (Phase 2e M1).
     *  Null for an application written before business profiles existed. */
    @Column(name = "business_profile_id")
    private UUID businessProfileId;

    @Column(name = "category", nullable = false)
    private String category = "";

    @Column(name = "description", nullable = false)
    private String description = "";

    @Column(name = "logo_url")
    private String logoUrl;

    @Column(name = "contact_name", nullable = false)
    private String contactName = "";

    @Column(name = "contact_phone", nullable = false)
    private String contactPhone = "";

    @Column(name = "contact_email", nullable = false)
    private String contactEmail = "";

    @Column(name = "country", nullable = false)
    private String country = "";

    @Column(name = "city", nullable = false)
    private String city = "";

    @Column(name = "address_line", nullable = false)
    private String addressLine = "";

    @Column(name = "latitude")
    private Double latitude;

    @Column(name = "longitude")
    private Double longitude;

    /** Written for the applicant to read, not as an internal note. */
    @Column(name = "review_note")
    private String reviewNote;

    /** What the approval created — a {@code delivery.merchant} id today. */
    @Column(name = "provisioned_ref_id")
    private UUID provisionedRefId;

    @Column(name = "submitted_at")
    private OffsetDateTime submittedAt;

    @Column(name = "reviewed_at")
    private OffsetDateTime reviewedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt = OffsetDateTime.now();

    /**
     * The stake, as a <em>record of a ledger movement</em> rather than a balance.
     *
     * <p>The money itself is in {@code payments}, as a transfer from this
     * person's AVAILABLE into their own STAKING bucket. Keeping a second copy of
     * the amount here would be a number that eventually disagrees with the
     * ledger; what these columns hold is what the application has to answer on
     * its own — has it been paid, and has the KYC fee come out of it yet.
     */
    @Column(name = "stake_amount_minor", nullable = false)
    private long stakeAmountMinor;

    @Column(name = "stake_paid_at")
    private OffsetDateTime stakePaidAt;

    @Column(name = "stake_released_at")
    private OffsetDateTime stakeReleasedAt;

    @Column(name = "kyc_fee_minor", nullable = false)
    private long kycFeeMinor;

    @Column(name = "kyc_fee_paid_at")
    private OffsetDateTime kycFeePaidAt;

    /** What community-verification rewards have taken out of the stake (Phase 3
     *  M5). Accumulated here for the same reason the KYC fee is: without it a
     *  driver whose stake has paid three rewards still looks fully staked, and a
     *  release would hand back money that is already somebody else's. */
    @Column(name = "reward_paid_minor", nullable = false)
    private long rewardPaidMinor;

    @Column(name = "reward_paid_at")
    private OffsetDateTime rewardPaidAt;

    protected PartnerAccount() {
    }

    PartnerAccount(UUID userId, PartnerKind kind, String businessName) {
        this.userId = userId;
        this.kind = kind;
        this.businessName = businessName;
    }

    void apply(String businessName, String category, String description, String logoUrl,
               String contactName, String contactPhone, String contactEmail,
               String country, String city, String addressLine,
               Double latitude, Double longitude, UUID businessProfileId) {
        this.businessName = businessName;
        this.businessProfileId = businessProfileId;
        this.category = orEmpty(category);
        this.description = orEmpty(description);
        this.logoUrl = logoUrl == null || logoUrl.isBlank() ? null : logoUrl;
        this.contactName = orEmpty(contactName);
        this.contactPhone = orEmpty(contactPhone);
        this.contactEmail = orEmpty(contactEmail);
        this.country = orEmpty(country);
        this.city = orEmpty(city);
        this.addressLine = orEmpty(addressLine);
        this.latitude = latitude;
        this.longitude = longitude;
        touch();
    }

    void submit(OffsetDateTime at) {
        this.status = PartnerStatus.SUBMITTED;
        this.submittedAt = at;
        // A resubmission clears the last verdict — leaving it up would show the
        // applicant a rejection reason next to an application under review.
        this.reviewNote = null;
        this.reviewedAt = null;
        touch();
    }

    /** Back to the applicant's hands, without touching what they've uploaded. */
    void withdraw() {
        this.status = PartnerStatus.DRAFT;
        this.submittedAt = null;
        touch();
    }

    void approve(UUID refId, OffsetDateTime at) {
        this.status = PartnerStatus.APPROVED;
        this.provisionedRefId = refId;
        this.reviewNote = null;
        this.reviewedAt = at;
        touch();
    }

    void reject(String note, OffsetDateTime at) {
        this.status = PartnerStatus.REJECTED;
        this.reviewNote = note;
        this.reviewedAt = at;
        touch();
    }

    /** Suspension keeps {@code provisionedRefId}: the merchant still exists,
     *  it is just switched off, and restoring must find it again. */
    void suspend(String note, OffsetDateTime at) {
        this.status = PartnerStatus.SUSPENDED;
        this.reviewNote = note;
        this.reviewedAt = at;
        touch();
    }

    void restore(OffsetDateTime at) {
        this.status = PartnerStatus.APPROVED;
        this.reviewNote = null;
        this.reviewedAt = at;
        touch();
    }

    // MARK: The stake

    /** Called once the ledger movement has actually happened, never before. */
    void recordStakePaid(long amountMinor, OffsetDateTime at) {
        this.stakeAmountMinor = amountMinor;
        this.stakePaidAt = at;
        this.stakeReleasedAt = null;
        touch();
    }

    void recordKycFeePaid(long amountMinor, OffsetDateTime at) {
        this.kycFeeMinor += amountMinor;
        this.kycFeePaidAt = at;
        touch();
    }

    /** A passenger was paid for verifying this partner's vehicle (Phase 3 M5).
     *  Accumulated, because a driver with three vehicles can earn three badges
     *  and each one costs them. */
    void recordRewardPaid(long amountMinor, OffsetDateTime at) {
        this.rewardPaidMinor += amountMinor;
        this.rewardPaidAt = at;
        touch();
    }

    void recordStakeReleased(OffsetDateTime at) {
        this.stakeReleasedAt = at;
        touch();
    }

    boolean hasLiveStake() {
        return stakePaidAt != null && stakeReleasedAt == null;
    }

    /** What is still locked: the stake less whatever the ID checks and the
     *  verification rewards have eaten. Never negative — a fee larger than the
     *  stake is a config mistake, not a debt somebody owes. */
    long remainingStakeMinor() {
        return hasLiveStake() ? Math.max(0, stakeAmountMinor - kycFeeMinor - rewardPaidMinor) : 0;
    }

    private void touch() {
        this.updatedAt = OffsetDateTime.now();
    }

    private static String orEmpty(String value) {
        return value == null ? "" : value.trim();
    }

    UUID getId() { return id; }
    UUID getUserId() { return userId; }
    PartnerKind getKind() { return kind; }
    PartnerStatus getStatus() { return status; }
    String getBusinessName() { return businessName; }
    UUID getBusinessProfileId() { return businessProfileId; }
    String getCategory() { return category; }
    String getDescription() { return description; }
    String getLogoUrl() { return logoUrl; }
    String getContactName() { return contactName; }
    String getContactPhone() { return contactPhone; }
    String getContactEmail() { return contactEmail; }
    String getCountry() { return country; }
    String getCity() { return city; }
    String getAddressLine() { return addressLine; }
    Double getLatitude() { return latitude; }
    Double getLongitude() { return longitude; }
    String getReviewNote() { return reviewNote; }
    UUID getProvisionedRefId() { return provisionedRefId; }
    OffsetDateTime getSubmittedAt() { return submittedAt; }
    OffsetDateTime getReviewedAt() { return reviewedAt; }
    OffsetDateTime getCreatedAt() { return createdAt; }
    OffsetDateTime getUpdatedAt() { return updatedAt; }
    long getStakeAmountMinor() { return stakeAmountMinor; }
    OffsetDateTime getStakePaidAt() { return stakePaidAt; }
    OffsetDateTime getStakeReleasedAt() { return stakeReleasedAt; }
    long getKycFeeMinor() { return kycFeeMinor; }
    long getRewardPaidMinor() { return rewardPaidMinor; }
}
