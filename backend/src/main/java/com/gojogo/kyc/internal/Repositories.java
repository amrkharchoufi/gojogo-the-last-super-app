package com.gojogo.kyc.internal;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

interface IdentityVerificationRepository extends JpaRepository<IdentityVerificationRecord, UUID> {

    Optional<IdentityVerificationRecord> findByUserId(UUID userId);

    /** How a webhook finds its person: it knows the vendor's id, not ours. */
    Optional<IdentityVerificationRecord> findByApplicantId(String applicantId);
}

interface ProviderEventRepository extends JpaRepository<ProviderEvent, String> {
}
