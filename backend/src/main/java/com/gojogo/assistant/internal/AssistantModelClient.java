package com.gojogo.assistant.internal;

import java.util.List;
import java.util.Map;
import java.util.function.Consumer;

/**
 * The one class in this codebase that knows where the model runs
 * (MADELEINE.md §2, MADELEINE-INFERENCE.md §5 rule 1).
 *
 * <p>Everything above it — the loop, the registry, the executor, the
 * confirmation protocol, the iOS client — speaks only this interface. There is
 * no {@code if (bedrock)} anywhere else, and there must never be one, because
 * that single fact is what makes the route a config change rather than a
 * rewrite: Bedrock on-demand today, self-hosted vLLM behind §6's switch trigger,
 * the same weights either way.
 *
 * <p>The security model is route-independent (rule 4). The {@code <user_content>}
 * delimiter, the registry's class check and the confirm-token protocol are all
 * server-side and above this line. <b>Changing route never changes what
 * Madeleine is allowed to do</b> — the wall was never in the model.
 */
interface AssistantModelClient {

    /**
     * One turn of the conversation.
     *
     * @param toolSchemas OpenAI-shaped function definitions, straight from the
     *                    registry. Pass an empty list for a call that must not
     *                    be able to call anything — which is how the sidekick is
     *                    kept out of the loop it is forbidden to run, by never
     *                    being handed a tool rather than by being told not to.
     * @param prose       receives assistant text as it becomes available.
     *                    <b>Called once per completion today</b>: M2 requests
     *                    non-streaming completions so the token counters are the
     *                    provider's exact {@code usage} numbers, which is what
     *                    §6's trigger is owed and what the eval measured. Turning
     *                    on SSE is a change inside this class — the sink is here
     *                    so it stays one.
     * @throws AssistantModelException on transport failure, a non-2xx, or a
     *                                 response that is not a chat completion.
     *                                 The loop turns that into an honest
     *                                 {@code turn_error}, never a fabricated reply
     */
    AssistantChatResult chat(AssistantModelRole role, List<AssistantChatMessage> messages,
                             List<Map<String, Object>> toolSchemas, Consumer<String> prose);

    /** The configured model id for a slot, for the turn log. */
    String modelId(AssistantModelRole role);

    /** What went wrong reaching the model. Deliberately one type: the loop's
     *  response to every failure is the same honest ending. */
    class AssistantModelException extends RuntimeException {

        AssistantModelException(String message) {
            super(message);
        }

        AssistantModelException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
