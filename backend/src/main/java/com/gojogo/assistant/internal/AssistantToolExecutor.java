package com.gojogo.assistant.internal;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * Runs one tool call — or, for a gated tool, declines to and asks the user
 * instead (MADELEINE.md §4 step 3, §5).
 *
 * <p><b>This class is the wall.</b> Read the {@code switch} below: the
 * {@code WRITE_GATED} branch writes an {@code AssistantAction} and returns
 * {@code PENDING_USER_APPROVAL}, and there is no other branch that could reach a
 * vertical for a gated tool — not one guarded by a flag, not one behind an
 * autonomy level, not one a prompt could unlock. Model output cannot execute a
 * gated side effect because the code to do so has not been written, and the
 * registry refuses to start if anybody writes it.
 *
 * <p>The switch is deliberately exhaustive over {@link AssistantToolClass}: a
 * fifth class added later fails compilation here, which is the right place to be
 * stopped.
 */
@Component
class AssistantToolExecutor {

    private static final Logger log = LoggerFactory.getLogger(AssistantToolExecutor.class);

    private final AssistantToolRegistry registry;
    private final AssistantResultTrimmer trimmer;
    private final AssistantActionRepository actions;
    private final AssistantPolicy policy;
    private final ObjectMapper json;

    AssistantToolExecutor(AssistantToolRegistry registry, AssistantResultTrimmer trimmer,
                          AssistantActionRepository actions, AssistantPolicy policy,
                          ObjectMapper json) {
        this.registry = registry;
        this.trimmer = trimmer;
        this.actions = actions;
        this.policy = policy;
        this.json = json;
    }

    AssistantToolOutcome execute(AssistantToolContext context, AssistantToolCall call) {
        Optional<AssistantTool> found = registry.find(call.name());
        if (found.isEmpty()) {
            // Counted as a parse failure because it is the same class of defect:
            // output that does not correspond to the catalog it was given.
            return AssistantToolOutcome.failed(call, payload("NO_SUCH_TOOL",
                "There is no tool by that name. Use only the tools you were given."), true);
        }
        AssistantTool tool = found.get();

        JsonNode args;
        try {
            args = call.arguments() == null || call.arguments().isBlank()
                ? json.createObjectNode() : json.readTree(call.arguments());
            if (!args.isObject()) {
                throw new IllegalArgumentException("arguments is not an object");
            }
        } catch (Exception malformed) {
            return AssistantToolOutcome.failed(call, payload("BAD_ARGUMENTS",
                "The arguments were not a JSON object. Send them again as one."), true);
        }

        return switch (tool.toolClass()) {
            case READ -> read(context, tool, call, args);
            case WRITE_GATED -> stage(context, tool, call);
            // Declared, classified, and not yet implemented — WRITE_SAFE lands
            // with M4 and CLIENT with M5. The registry does not offer these, so
            // reaching one means the model invented it; saying so plainly is
            // what the system prompt already tells it to expect.
            case WRITE_SAFE, CLIENT -> AssistantToolOutcome.failed(call, payload(
                "TOOL_NOT_AVAILABLE",
                "This tool is not available in this version of the app. Say so plainly."), false);
        };
    }

    // MARK: READ

    private AssistantToolOutcome read(AssistantToolContext context, AssistantTool tool,
                                      AssistantToolCall call, JsonNode args) {
        Object result;
        try {
            result = tool.handler().run(context, args);
        } catch (ResponseStatusException refused) {
            // A vertical's own 4xx wording is the product — the app shows the
            // server's words — and it is safe to pass on: it is what the user
            // would have seen by tapping.
            result = Map.of("error", "REFUSED", "message",
                refused.getReason() == null ? "Not allowed." : refused.getReason());
        } catch (RuntimeException e) {
            // Anything else is ours and stays ours: the model gets a fact, the
            // log gets the stack.
            log.warn("Madeleine tool {} failed", tool.name(), e);
            result = Map.of("error", "TOOL_FAILED",
                "message", "This lookup failed. Do not retry it more than once.");
        }
        String trimmed = trimmer.trim(result);
        // §4's untrusted-content rule. The delimiter is the first fence; the
        // wall is that nothing inside it can reach a gated action.
        String payload = tool.userAuthored()
            ? "<user_content>" + trimmed + "</user_content>"
            : trimmed;
        return new AssistantToolOutcome(call, payload, trimmed, null, false);
    }

    // MARK: WRITE_GATED — the wall

    private AssistantToolOutcome stage(AssistantToolContext context, AssistantTool tool,
                                       AssistantToolCall call) {
        // §5 step 5: one action, one approval. A second identical call while a
        // card is already on screen must not produce a second card — the model
        // is told the first one is still waiting, which is also the behaviour
        // the eval scores as "did not retry a gated action".
        Optional<AssistantAction> live = actions
            .findFirstByTurnIdAndToolNameAndStateOrderByCreatedAtDesc(
                context.turnId(), tool.name(), AssistantActionState.PENDING)
            .filter(existing -> existing.isLive(OffsetDateTime.now()));
        if (live.isPresent()) {
            return new AssistantToolOutcome(call, payload("PENDING_USER_APPROVAL",
                "This is already waiting for the user's approval. Do not call it again."),
                "already awaiting approval", live.get().getId(), false);
        }

        AssistantAction action = actions.save(new AssistantAction(
            context.conversationId(), null, context.turnId(), tool.name(), call.arguments(),
            AssistantActionSummaries.summaryFor(tool.name()),
            // Deliberately null. §5 requires the exact amount to be computed by
            // the owning vertical's quote path, never by the model — so it is
            // not lifted out of the model's own arguments here. M4 owns
            // execution and therefore owns the number; until it lands, a card
            // with no amount must never be approvable for a money action.
            null, null,
            OffsetDateTime.now().plusMinutes(policy.actionTtlMinutes())));

        return new AssistantToolOutcome(call, payload("PENDING_USER_APPROVAL",
            "The user is being shown a confirmation card. Tell them what you queued and stop."),
            "awaiting approval", action.getId(), false);
    }

    private String payload(String status, String detail) {
        try {
            return json.writeValueAsString(Map.of("status", status, "detail", detail));
        } catch (Exception impossible) {
            return "{\"status\":\"" + status + "\"}";
        }
    }

    /**
     * The outcome of one tool call.
     *
     * @param payload       what enters the model's context
     * @param ledgerSummary what the {@code AssistantMessage} row records — the
     *                      trimmed result, never the raw one, and never the
     *                      {@code <user_content>} wrapper, which is context
     *                      plumbing rather than part of the story
     * @param actionId      the card this call raised, or null
     * @param parseFailure  output that did not correspond to the catalog it was
     *                      given; the number MADELEINE-INFERENCE.md §9 tracks
     */
    record AssistantToolOutcome(AssistantToolCall call, String payload, String ledgerSummary,
                                UUID actionId, boolean parseFailure) {

        static AssistantToolOutcome failed(AssistantToolCall call, String payload,
                                           boolean parseFailure) {
            return new AssistantToolOutcome(call, payload, payload, null, parseFailure);
        }
    }
}
