package com.gojogo.share.internal;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

interface ShareTokenRepository extends JpaRepository<ShareToken, UUID> {

    Optional<ShareToken> findByToken(String token);

    List<ShareToken> findByKindAndRefIdAndOwnerIdOrderByCreatedAtDesc(String kind, UUID refId,
                                                                      UUID ownerId);

    /** The purge. Expired rows are kept for a while — a link that stopped
     *  working yesterday should 404 rather than vanish, so the person holding it
     *  gets "this has ended" and not "this never existed". */
    List<ShareToken> findByExpiresAtBefore(OffsetDateTime cutoff, Pageable page);
}
