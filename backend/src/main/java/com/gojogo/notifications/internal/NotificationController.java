package com.gojogo.notifications.internal;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.OffsetDateTime;

/**
 * In-app activity feed. All Bearer-authed; the feed belongs to the caller.
 */
@RestController
class NotificationController {

    private final NotificationService notifications;
    private final NotificationCurrentProfile current;

    NotificationController(NotificationService notifications, NotificationCurrentProfile current) {
        this.notifications = notifications;
        this.current = current;
    }

    @GetMapping("/v1/notifications")
    NotificationsPage list(@AuthenticationPrincipal Jwt jwt,
                           @RequestParam(required = false)
                           @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) OffsetDateTime before,
                           @RequestParam(defaultValue = "30") int limit) {
        return notifications.list(current.require(jwt).id(), before, limit);
    }

    @GetMapping("/v1/notifications/unread-count")
    UnreadCountDto unreadCount(@AuthenticationPrincipal Jwt jwt) {
        return new UnreadCountDto(notifications.unreadCount(current.require(jwt).id()));
    }

    @PostMapping("/v1/notifications/read")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void markRead(@AuthenticationPrincipal Jwt jwt) {
        notifications.markAllRead(current.require(jwt).id());
    }
}
