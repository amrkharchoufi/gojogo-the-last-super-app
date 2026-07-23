package com.gojogo.notifications.internal;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Device-token registration for APNs push. */
@RestController
class PushController {

    private final NotificationService notifications;
    private final NotificationCurrentProfile current;

    PushController(NotificationService notifications, NotificationCurrentProfile current) {
        this.notifications = notifications;
        this.current = current;
    }

    @PostMapping("/v1/push/register")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void register(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody RegisterPushRequest request) {
        notifications.registerDevice(current.require(jwt).id(), request.token(),
            request.platform() == null ? "ios" : request.platform());
    }

    @PostMapping("/v1/push/unregister")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void unregister(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody UnregisterPushRequest request) {
        notifications.unregisterDevice(request.token());
    }
}

record RegisterPushRequest(@NotBlank String token, String platform) {
}

record UnregisterPushRequest(@NotBlank String token) {
}
