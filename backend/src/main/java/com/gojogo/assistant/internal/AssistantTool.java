package com.gojogo.assistant.internal;

import com.fasterxml.jackson.databind.JsonNode;

import java.util.Map;
import java.util.UUID;

/*
 * One registered tool, the code behind it, and the context it runs in.
 */

/**
 * A tool as the registry knows it.
 *
 * @param handler         null for anything this build cannot execute — which
 *                        includes every {@code WRITE_GATED} tool, permanently:
 *                        their implementation is the wall, not a method
 * @param userAuthored    whether the result can carry text a user wrote, and so
 *                        must be wrapped in {@code <user_content>} before it
 *                        enters context (MADELEINE.md §4)
 */
record AssistantTool(String name, AssistantToolClass toolClass, Map<String, Object> schema,
                     AssistantToolHandler handler, boolean userAuthored) {

    /** Whether the model should be told this tool exists. */
    boolean offerable() {
        return toolClass == AssistantToolClass.WRITE_GATED || handler != null;
    }
}

/** What a READ tool actually does. Returns anything Jackson can serialise. */
@FunctionalInterface
interface AssistantToolHandler {

    Object run(AssistantToolContext context, JsonNode args);
}

/**
 * Who a tool call is running as.
 *
 * <p><b>{@code userId} is the whole of Madeleine's authority</b> (locked
 * decision #1): every facade call carries it, so a tool reaches exactly what
 * this person could reach by tapping, and not one row further. There is no
 * service account here to borrow.
 */
record AssistantToolContext(UUID userId, UUID conversationId, UUID turnId) {
}
