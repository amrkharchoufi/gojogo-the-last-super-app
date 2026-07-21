package com.gojogo.profile.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
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

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    protected UserProfile() {
    }

    UserProfile(String cognitoSub, String email) {
        this.cognitoSub = cognitoSub;
        this.email = email;
        this.createdAt = OffsetDateTime.now();
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
}
