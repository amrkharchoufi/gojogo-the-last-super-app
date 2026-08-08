package com.gojogo.assistant.internal;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * MADELEINE.md §3's REST surface, as far as M2 builds it.
 *
 * <p>Every path is authenticated as the user by the platform chain
 * ({@code anyRequest().authenticated()}), and every one of them scopes its read
 * to the caller's own conversations — a conversation belonging to somebody else
 * is 404, not 403, because "you may not see this" still confirms there is a
 * this.
 *
 * <p><b>What is deliberately absent</b>, so that a missing route reads as a
 * milestone boundary rather than an oversight: {@code /actions/{id}/approve} and
 * {@code /decline} are M4's — the actions they act on are already being written,
 * and shipping the approval half without the execution half would put a button
 * on screen that does nothing. {@code /tasks} is M6's, {@code /pilot/ack} and
 * {@code /turns/{id}/interrupt} are M5's.
 */
@RestController
class AssistantController {

    private final AssistantService assistant;
    private final AssistantCurrentProfile profiles;

    AssistantController(AssistantService assistant, AssistantCurrentProfile profiles) {
        this.assistant = assistant;
        this.profiles = profiles;
    }

    @PostMapping("/v1/assistant/conversations")
    @ResponseStatus(HttpStatus.CREATED)
    AssistantDtos.ConversationDto open(@AuthenticationPrincipal Jwt jwt) {
        return assistant.open(profiles.require(jwt).id());
    }

    @GetMapping("/v1/assistant/conversations")
    List<AssistantDtos.ConversationDto> list(@AuthenticationPrincipal Jwt jwt,
                                             @RequestParam(defaultValue = "20") int limit) {
        return assistant.list(profiles.require(jwt).id(), limit);
    }

    /** The replay view. A client that missed socket events catches up here. */
    @GetMapping("/v1/assistant/conversations/{conversationId}")
    AssistantDtos.ConversationDetailDto replay(@AuthenticationPrincipal Jwt jwt,
                                               @PathVariable UUID conversationId) {
        return assistant.replay(profiles.require(jwt).id(), conversationId);
    }

    /**
     * Starts an agent turn. 202, not 200: the loop may run for up to
     * {@code turnDeadlineSeconds} and reports over the WorldSocket, so the
     * request returns as soon as the message is durably on the ledger.
     */
    @PostMapping("/v1/assistant/conversations/{conversationId}/messages")
    @ResponseStatus(HttpStatus.ACCEPTED)
    AssistantDtos.TurnStartedDto post(@AuthenticationPrincipal Jwt jwt,
                                      @PathVariable UUID conversationId,
                                      @Valid @RequestBody AssistantDtos.PostMessageRequest body) {
        UUID turnId = assistant.postMessage(profiles.require(jwt).id(), conversationId,
            body.text().strip());
        return new AssistantDtos.TurnStartedDto(turnId);
    }
}
