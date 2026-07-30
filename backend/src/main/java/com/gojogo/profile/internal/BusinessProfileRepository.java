package com.gojogo.profile.internal;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

interface BusinessProfileRepository extends JpaRepository<BusinessProfile, UUID> {

    List<BusinessProfile> findByOwnerProfileIdOrderByCreatedAtDesc(UUID ownerProfileId);

    long countByOwnerProfileId(UUID ownerProfileId);
}
