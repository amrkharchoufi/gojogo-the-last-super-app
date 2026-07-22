package com.gojogo.profile.internal;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

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

    @Column(name = "cognito_sub", nullable = false, unique = true, length = 64)
    private String cognitoSub;

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

    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(name = "user_interest", schema = "profile",
        joinColumns = @JoinColumn(name = "profile_id"))
    @Column(name = "interest", nullable = false, length = 60)
    private Set<String> interests = new HashSet<>();

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    protected UserProfile() {
    }

    UserProfile(String cognitoSub, String email, String handle) {
        this.cognitoSub = cognitoSub;
        this.email = email;
        this.handle = handle;
        this.createdAt = OffsetDateTime.now();
        this.updatedAt = OffsetDateTime.now();
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

    void setInterests(Set<String> interests) {
        this.interests = new HashSet<>(interests);
    }
}
