package com.gojogo.assistant.internal;

import java.util.List;

/*
 * The wire-neutral vocabulary the loop speaks to a model.
 *
 * Deliberately shaped like OpenAI chat completions, because that is what both
 * routes serve (MADELEINE-INFERENCE.md §5 rule 2: vLLM natively, Bedrock on the
 * bedrock-mantle endpoint). Shaping it like anything else would put a
 * translation layer in the loop, which is the one place rule 1 forbids knowing
 * about the route.
 */

/** Which slot a call is for. The loop never picks a model id — it picks a job,
 *  and {@link AssistantModelClient} maps that to whatever is configured. */
enum AssistantModelRole {

    /** Plans and calls tools (MADELEINE.md §4). */
    BRAIN,

    /**
     * Triage, tool-result summarisation, conversation titles (§2). Never plans,
     * never calls a tool — not by convention but because nothing here ever
     * hands it a tool schema.
     */
    SIDEKICK
}

/**
 * One message in the model's context.
 *
 * @param role       {@code system}, {@code user}, {@code assistant} or {@code tool}
 * @param toolCalls  what an assistant message asked to run; empty otherwise
 * @param toolCallId which call a {@code tool} message answers; null otherwise
 */
record AssistantChatMessage(String role, String content, List<AssistantToolCall> toolCalls,
                            String toolCallId) {

    static AssistantChatMessage system(String content) {
        return new AssistantChatMessage("system", content, List.of(), null);
    }

    static AssistantChatMessage user(String content) {
        return new AssistantChatMessage("user", content, List.of(), null);
    }

    static AssistantChatMessage assistant(String content) {
        return new AssistantChatMessage("assistant", content, List.of(), null);
    }

    static AssistantChatMessage assistantCalling(String content, List<AssistantToolCall> calls) {
        return new AssistantChatMessage("assistant", content, calls, null);
    }

    static AssistantChatMessage toolResult(String toolCallId, String content) {
        return new AssistantChatMessage("tool", content, List.of(), toolCallId);
    }
}

/**
 * One tool call as the model emitted it.
 *
 * @param arguments raw JSON text, kept unparsed here on purpose: a call whose
 *                  arguments will not parse is a measurable failure mode
 *                  (MADELEINE-INFERENCE.md §9) and has to survive as far as the
 *                  executor to be counted rather than thrown at the wire
 */
record AssistantToolCall(String id, String name, String arguments) {
}

/**
 * What one model call returned.
 *
 * @param inputTokens  what the provider says it charged for, not an estimate —
 *                     MADELEINE-INFERENCE.md §6's switch trigger is a money
 *                     decision and deserves the provider's own number
 * @param finishReason the provider's word for why generation stopped, carried
 *                     through for the turn log; the loop decides on tool calls
 */
record AssistantChatResult(String content, List<AssistantToolCall> toolCalls,
                           int inputTokens, int outputTokens, String finishReason) {

    boolean hasToolCalls() {
        return toolCalls != null && !toolCalls.isEmpty();
    }
}
