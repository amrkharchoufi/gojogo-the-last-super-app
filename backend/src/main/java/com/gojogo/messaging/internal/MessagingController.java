package com.gojogo.messaging.internal;

import jakarta.validation.Valid;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/**
 * My World messaging REST surface. Everything requires a Cognito bearer token;
 * the caller is resolved to a profile via {@link CurrentProfile}. Writes here
 * are durable; recipients also get a real-time copy over the WebSocket.
 */
@RestController
class MessagingController {

    private final MessagingService messaging;
    private final CurrentProfile current;

    MessagingController(MessagingService messaging, CurrentProfile current) {
        this.messaging = messaging;
        this.current = current;
    }

    @GetMapping("/v1/conversations")
    List<ConversationDto> conversations(@AuthenticationPrincipal Jwt jwt) {
        return messaging.listConversations(current.require(jwt).id());
    }

    @PostMapping("/v1/conversations")
    @ResponseStatus(HttpStatus.CREATED)
    ConversationDto create(@AuthenticationPrincipal Jwt jwt,
                           @Valid @RequestBody CreateConversationRequest request) {
        return messaging.createConversation(current.require(jwt).id(), request);
    }

    @GetMapping("/v1/conversations/{convId}/messages")
    MessagesResponse messages(@AuthenticationPrincipal Jwt jwt,
                              @PathVariable UUID convId,
                              @RequestParam(required = false)
                              @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) OffsetDateTime before,
                              @RequestParam(defaultValue = "30") int limit) {
        Instant beforeInstant = before != null ? before.toInstant() : null;
        return messaging.listMessages(current.require(jwt).id(), convId, beforeInstant, limit);
    }

    @PostMapping("/v1/conversations/{convId}/messages")
    @ResponseStatus(HttpStatus.CREATED)
    MessageDto send(@AuthenticationPrincipal Jwt jwt,
                    @PathVariable UUID convId,
                    @Valid @RequestBody SendMessageRequest request) {
        return messaging.sendMessage(current.require(jwt).id(), convId, request);
    }

    @PostMapping("/v1/conversations/{convId}/messages/{msgId}/reactions")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void react(@AuthenticationPrincipal Jwt jwt,
               @PathVariable UUID convId, @PathVariable UUID msgId,
               @Valid @RequestBody ReactRequest request) {
        messaging.react(current.require(jwt).id(), convId, msgId, request.tapback());
    }

    @DeleteMapping("/v1/conversations/{convId}/messages/{msgId}/reactions")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void unreact(@AuthenticationPrincipal Jwt jwt,
                 @PathVariable UUID convId, @PathVariable UUID msgId) {
        messaging.unreact(current.require(jwt).id(), convId, msgId);
    }

    @PostMapping("/v1/conversations/{convId}/messages/{msgId}/poll/vote")
    MessageDto vote(@AuthenticationPrincipal Jwt jwt,
                    @PathVariable UUID convId, @PathVariable UUID msgId,
                    @Valid @RequestBody VotePollRequest request) {
        return messaging.votePoll(current.require(jwt).id(), convId, msgId, request.optionId());
    }

    @PostMapping("/v1/conversations/{convId}/read")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void read(@AuthenticationPrincipal Jwt jwt,
              @PathVariable UUID convId, @Valid @RequestBody MarkReadRequest request) {
        messaging.markRead(current.require(jwt).id(), convId, request.lastReadMessageId());
    }

    @PostMapping("/v1/conversations/{convId}/typing")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void typing(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID convId) {
        messaging.typing(current.require(jwt).id(), convId);
    }

    @PostMapping("/v1/conversations/{convId}/pin")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void pin(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID convId,
             @RequestParam(defaultValue = "true") boolean pinned) {
        messaging.setPinned(current.require(jwt).id(), convId, pinned);
    }

    @DeleteMapping("/v1/conversations/{convId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void leave(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID convId) {
        messaging.leave(current.require(jwt).id(), convId);
    }
}
