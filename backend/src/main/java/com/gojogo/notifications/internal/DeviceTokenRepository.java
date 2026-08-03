package com.gojogo.notifications.internal;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

interface DeviceTokenRepository extends JpaRepository<DeviceToken, UUID> {

    Optional<DeviceToken> findByToken(String token);

    List<DeviceToken> findByProfileId(UUID profileId);

    /** Server-side cleanup only — APNs told us this token is dead, so it goes
     *  whoever it belongs to. A user-initiated unregister must use the
     *  caller-scoped delete below instead. */
    @Transactional
    void deleteByToken(String token);

    /** A user unregistering their own device: the row only goes if it is
     *  theirs, so one account cannot delete another's push registration by
     *  presenting its token. */
    @Transactional
    void deleteByProfileIdAndToken(UUID profileId, String token);
}
