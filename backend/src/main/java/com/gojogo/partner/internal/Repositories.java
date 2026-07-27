package com.gojogo.partner.internal;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

interface PartnerAccountRepository extends JpaRepository<PartnerAccount, UUID> {

    Optional<PartnerAccount> findByUserIdAndKind(UUID userId, PartnerKind kind);

    List<PartnerAccount> findByUserIdOrderByCreatedAtAsc(UUID userId);

    /** The reviewer's queue: one status at a time, oldest submission first. */
    List<PartnerAccount> findByStatusInOrderBySubmittedAtAscCreatedAtAsc(
        Collection<PartnerStatus> statuses, Pageable page);
}

interface PartnerDocumentRepository extends JpaRepository<PartnerDocument, UUID> {

    List<PartnerDocument> findByAccountIdOrderByKindAsc(UUID accountId);

    Optional<PartnerDocument> findByAccountIdAndKind(UUID accountId, DocumentKind kind);

    List<PartnerDocument> findByAccountIdInOrderByKindAsc(Collection<UUID> accountIds);
}
