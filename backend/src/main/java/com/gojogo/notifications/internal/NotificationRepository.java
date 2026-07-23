package com.gojogo.notifications.internal;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

interface NotificationRepository extends JpaRepository<Notification, UUID> {

    List<Notification> findByRecipientIdOrderByCreatedAtDesc(UUID recipientId, Limit limit);

    List<Notification> findByRecipientIdAndCreatedAtBeforeOrderByCreatedAtDesc(
        UUID recipientId, OffsetDateTime before, Limit limit);

    long countByRecipientIdAndReadFalse(UUID recipientId);

    @Modifying
    @Query("update Notification n set n.read = true where n.recipientId = :recipientId and n.read = false")
    int markAllRead(@Param("recipientId") UUID recipientId);
}
