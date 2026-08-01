package com.gojogo.profile.internal;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

import com.gojogo.profile.ProfileKind;

import java.time.OffsetDateTime;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

@Entity
@Table(name = "user_profile", schema = "profile")
class UserProfile {

    @Id
    @GeneratedValue
    private UUID id;

    /** Null for a business — a business has no sign-in of its own, its owner does. */
    @Column(name = "cognito_sub", unique = true, length = 64)
    private String cognitoSub;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private ProfileKind kind = ProfileKind.PERSON;

    @Column(length = 320)
    private String email;

    @Column(name = "display_name", length = 120)
    private String displayName;

    @Column(nullable = false, unique = true, length = 60)
    private String handle;

    @Column(nullable = false)
    private String bio = "";

    @Column(nullable = false, length = 60)
    private String category = "Creator";

    @Column(name = "birth_year")
    private Integer birthYear;

    @Column(name = "avatar_url")
    private String avatarUrl;

    @Column(name = "handle_changed_at")
    private OffsetDateTime handleChangedAt;

    @Column(name = "handle_change_count", nullable = false)
    private int handleChangeCount;

    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(name = "user_interest", schema = "profile",
        joinColumns = @JoinColumn(name = "profile_id"))
    @Column(name = "interest", nullable = false, length = 60)
    private Set<String> interests = new HashSet<>();

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    /** When this person asked to be deleted. Sign-in was disabled the same
     *  instant; this column is the clock the grace period runs on (V28). */
    @Column(name = "deletion_requested_at")
    private OffsetDateTime deletionRequestedAt;

    /** When the grace ran out and the row was actually scrubbed. */
    @Column(name = "anonymized_at")
    private OffsetDateTime anonymizedAt;

    protected UserProfile() {
    }

    UserProfile(String cognitoSub, String email, String handle) {
        this.cognitoSub = cognitoSub;
        this.email = email;
        this.handle = handle;
        this.createdAt = OffsetDateTime.now();
        this.updatedAt = OffsetDateTime.now();
    }

    /** A business profile: no Cognito subject, no email of its own. */
    static UserProfile business(String handle, String displayName) {
        UserProfile profile = new UserProfile(null, null, handle);
        profile.kind = ProfileKind.BUSINESS;
        profile.displayName = displayName;
        return profile;
    }

    @PreUpdate
    void touch() {
        this.updatedAt = OffsetDateTime.now();
    }

    UUID getId() {
        return id;
    }

    String getCognitoSub() {
        return cognitoSub;
    }

    ProfileKind getKind() {
        return kind;
    }

    String getEmail() {
        return email;
    }

    String getDisplayName() {
        return displayName;
    }

    String getHandle() {
        return handle;
    }

    String getBio() {
        return bio;
    }

    String getCategory() {
        return category;
    }

    Integer getBirthYear() {
        return birthYear;
    }

    String getAvatarUrl() {
        return avatarUrl;
    }

    Set<String> getInterests() {
        return interests;
    }

    void setDisplayName(String displayName) {
        this.displayName = displayName;
    }

    void setHandle(String handle) {
        this.handle = handle;
    }

    void setBio(String bio) {
        this.bio = bio;
    }

    void setCategory(String category) {
        this.category = category;
    }

    void setBirthYear(Integer birthYear) {
        this.birthYear = birthYear;
    }

    void setAvatarUrl(String avatarUrl) {
        this.avatarUrl = avatarUrl;
    }

    OffsetDateTime getHandleChangedAt() {
        return handleChangedAt;
    }

    void setHandleChangedAt(OffsetDateTime handleChangedAt) {
        this.handleChangedAt = handleChangedAt;
    }

    int getHandleChangeCount() {
        return handleChangeCount;
    }

    void recordHandleChange() {
        this.handleChangedAt = OffsetDateTime.now();
        this.handleChangeCount++;
    }

    void setInterests(Set<String> interests) {
        this.interests = new HashSet<>(interests);
    }

    OffsetDateTime getDeletionRequestedAt() {
        return deletionRequestedAt;
    }

    OffsetDateTime getAnonymizedAt() {
        return anonymizedAt;
    }

    void requestDeletion() {
        this.deletionRequestedAt = OffsetDateTime.now();
    }

    void cancelDeletion() {
        this.deletionRequestedAt = null;
    }

    /**
     * The scrub itself.
     *
     * <p><b>The row survives and the person does not.</b> Deleting it would take
     * every foreign key that points at it — and, more to the point, would leave
     * holes in other people's threads, because every author summary in this
     * codebase reads a profile. What is removed is everything that identifies
     * somebody: name, handle, email, avatar, bio, birth year, interests, and the
     * Cognito subject that tied the row to a login. What is left is an id, which
     * is what turns their old posts into "Deleted user" everywhere, for free.
     *
     * <p>Clearing {@code cognitoSub} is also what lets the same person sign up
     * again later with the same email: they get a new, empty profile rather than
     * walking back into the one they asked us to destroy.
     *
     * @param tombstoneHandle a unique, obviously-dead handle — the column is
     *                        NOT NULL and UNIQUE, so it cannot simply be emptied
     */
    void anonymize(String tombstoneHandle) {
        this.cognitoSub = null;
        this.email = null;
        this.displayName = null;
        this.handle = tombstoneHandle;
        this.bio = "";
        this.category = "";
        this.birthYear = null;
        this.avatarUrl = null;
        this.interests = new HashSet<>();
        this.anonymizedAt = OffsetDateTime.now();
    }
}
