package com.gojogo.assistant.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;

/**
 * Conversations, and the decision to let a turn start (MADELEINE.md §3, §4).
 *
 * <p>Two admission rules from §4, and they are enforced differently on purpose:
 *
 * <ul>
 *   <li><b>{@code turnsPerUserPerHour}</b> is counted from the ledger, so it
 *       holds across every Fargate task rather than per instance. A rate limit
 *       that a second container silently doubles is not a rate limit.</li>
 *   <li><b>{@code concurrentTurnsPerUser=1}</b> is enforced by chaining a user's
 *       turns onto one another, so <em>a second message queues, it does not
 *       fork</em> — the spec's words, and the reason it queues rather than being
 *       refused is that a person typing twice meant both things. This one is
 *       per-instance: the chain lives in memory. Today the service runs a single
 *       task and a user's requests land on it; the day it does not, two
 *       simultaneous turns for one person become possible, and the fix is a
 *       claim row rather than a bigger map. Worth writing down rather than
 *       discovering.</li>
 * </ul>
 */
@Service
class AssistantService {

    private static final Logger log = LoggerFactory.getLogger(AssistantService.class);

    private final AssistantConversationRepository conversations;
    private final AssistantMessageRepository messages;
    private final AssistantActionRepository actions;
    private final AssistantLedger ledger;
    private final AssistantTurnRunner runner;
    private final AssistantPolicy policy;
    private final AssistantTitler titler;
    private final ExecutorService turnPool;

    /** One user, one running turn. See the class javadoc for the caveat. */
    private final ConcurrentHashMap<UUID, CompletableFuture<Void>> chains =
        new ConcurrentHashMap<>();

    AssistantService(AssistantConversationRepository conversations,
                     AssistantMessageRepository messages, AssistantActionRepository actions,
                     AssistantLedger ledger, AssistantTurnRunner runner, AssistantPolicy policy,
                     AssistantTitler titler, ExecutorService assistantTurnPool) {
        this.conversations = conversations;
        this.messages = messages;
        this.actions = actions;
        this.ledger = ledger;
        this.runner = runner;
        this.policy = policy;
        this.titler = titler;
        this.turnPool = assistantTurnPool;
    }

    @Transactional
    AssistantDtos.ConversationDto open(UUID userId) {
        return AssistantDtos.ConversationDto.of(
            conversations.save(new AssistantConversation(userId)));
    }

    @Transactional(readOnly = true)
    List<AssistantDtos.ConversationDto> list(UUID userId, int limit) {
        return conversations.findByUserIdAndStateOrderByLastActiveAtDesc(userId,
                AssistantConversationState.ACTIVE, PageRequest.of(0, Math.clamp(limit, 1, 50)))
            .stream()
            .map(AssistantDtos.ConversationDto::of)
            .toList();
    }

    /**
     * The replay view (§3): every ledger row, and the cards still waiting.
     *
     * <p>This is what a client that missed socket events reads on foreground,
     * which is why the socket can be best-effort at all.
     *
     * <p><b>No confirm tokens.</b> A card is listed with its summary and its
     * expiry; the token that would approve it travels only on the live socket
     * event, so a replayed conversation cannot be used to approve anything.
     */
    @Transactional(readOnly = true)
    AssistantDtos.ConversationDetailDto replay(UUID userId, UUID conversationId) {
        AssistantConversation conversation = require(userId, conversationId);
        OffsetDateTime now = OffsetDateTime.now();
        return new AssistantDtos.ConversationDetailDto(
            AssistantDtos.ConversationDto.of(conversation),
            messages.findByConversationIdOrderBySeqAsc(conversationId).stream()
                .map(AssistantDtos.MessageDto::of)
                .toList(),
            actions.findByConversationIdOrderByCreatedAtDesc(conversationId,
                    PageRequest.of(0, 20)).stream()
                .filter(action -> action.isLive(now))
                .map(AssistantDtos.PendingActionDto::of)
                .toList());
    }

    /**
     * Accepts a user message and starts a turn.
     *
     * <p>Returns as soon as the message is durably on the ledger; the turn runs
     * on its own thread and reports over the socket. That is §3's 202 — a loop
     * that can take two minutes has no business holding an HTTP connection, and
     * the ledger is what makes returning early safe.
     */
    UUID postMessage(UUID userId, UUID conversationId, String text) {
        require(userId, conversationId);
        long recent = messages.turnsSince(userId, OffsetDateTime.now().minusHours(1));
        if (recent >= policy.turnsPerUserPerHour()) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                "You have reached the hourly limit for Madeleine. Try again shortly.");
        }
        UUID turnId = UUID.randomUUID();
        ledger.recordUserMessage(conversationId, turnId, text);

        // Chain rather than fork: the next turn for this user starts when the
        // current one finishes, whatever it finished as.
        chains.compute(userId, (key, previous) -> {
            CompletableFuture<Void> ran = previous == null || previous.isDone()
                ? CompletableFuture.runAsync(
                    () -> runner.run(userId, conversationId, turnId, text), turnPool)
                : previous.handle((ignored, error) -> null).thenRunAsync(
                    () -> runner.run(userId, conversationId, turnId, text), turnPool);
            return ran.handle((ignored, error) -> {
                if (error != null) {
                    // The runner does not throw; this is the belt on top of it.
                    log.error("Madeleine turn {} escaped the runner", turnId, error);
                }
                return null;
            });
        });
        titler.titleIfUnnamed(conversationId, text);
        return turnId;
    }

    private AssistantConversation require(UUID userId, UUID conversationId) {
        return conversations.findByIdAndUserId(conversationId, userId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such conversation"));
    }
}
