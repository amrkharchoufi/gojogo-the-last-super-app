package com.gojogo.assistant.internal;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.util.List;


/**
 * What a tool returns, cut down to what should enter the brain's context
 * (MADELEINE.md §4 step 4).
 *
 * <p>Two stages, in order:
 *
 * <ol>
 *   <li><b>Cap the lists</b> at {@code toolResultMaxItems}, saying so. A model
 *       that is told the list was cut can ask for a narrower query; one that is
 *       silently handed the first eight believes it saw everything.</li>
 *   <li><b>Summarise anything still oversized</b> with the sidekick, whose whole
 *       reason for existing is to keep the brain's tokens for thinking rather
 *       than for reading JSON — a cost decision as much as a quality one.</li>
 * </ol>
 *
 * <p>The sidekick's summary is measured for <em>faithfulness</em> rather than
 * fluency, because §4 pipes it straight into the brain's context where an
 * invented price is a fact the brain cannot detect. Across every sidekick
 * candidate and every run of the eval there were zero hallucinated facts — but
 * the prompt that achieved that is the one lifted into
 * {@link AssistantPrompts#SUMMARIZE}, not a paraphrase of it.
 *
 * <p><b>Never throws.</b> A summariser that fails takes the truncated JSON with
 * it, which is degraded but true; failing the tool call would lose a result the
 * vertical already computed.
 */
@Component
class AssistantResultTrimmer {

    private static final Logger log = LoggerFactory.getLogger(AssistantResultTrimmer.class);

    private final ObjectMapper json;
    private final AssistantModelClient models;
    private final AssistantPolicy policy;

    AssistantResultTrimmer(ObjectMapper json, AssistantModelClient models,
                           AssistantPolicy policy) {
        this.json = json;
        this.models = models;
        this.policy = policy;
    }

    /**
     * @param result whatever the handler returned
     * @return the text that will enter context — JSON, or prose when the
     *         sidekick was needed
     */
    String trim(Object result) {
        JsonNode node;
        try {
            node = json.valueToTree(result);
        } catch (RuntimeException e) {
            log.warn("Madeleine tool result would not serialise", e);
            return "{\"error\":\"RESULT_UNREADABLE\"}";
        }
        capLists(node, policy.toolResultMaxItems());

        String text;
        try {
            text = json.writeValueAsString(node);
        } catch (Exception e) {
            return "{\"error\":\"RESULT_UNREADABLE\"}";
        }
        int maxChars = policy.toolResultMaxChars();
        if (text.length() <= maxChars) {
            return text;
        }
        return summarise(text, maxChars);
    }

    /** Caps every array in the tree, marking the object that held it. */
    private static void capLists(JsonNode node, int maxItems) {
        if (node instanceof ObjectNode object) {
            List<String> fields = new java.util.ArrayList<>();
            object.fieldNames().forEachRemaining(fields::add);
            for (String field : fields) {
                JsonNode child = object.get(field);
                if (child instanceof ArrayNode array && array.size() > maxItems) {
                    int total = array.size();
                    while (array.size() > maxItems) {
                        array.remove(array.size() - 1);
                    }
                    object.put(field + "Total", total);
                    object.put(field + "Truncated", true);
                } else {
                    capLists(child, maxItems);
                }
            }
        } else if (node instanceof ArrayNode array) {
            array.forEach(child -> capLists(child, maxItems));
        }
    }

    private String summarise(String text, int maxChars) {
        try {
            AssistantChatResult summary = models.chat(AssistantModelRole.SIDEKICK,
                List.of(AssistantChatMessage.system(AssistantPrompts.SUMMARIZE),
                    AssistantChatMessage.user(text)),
                List.of(),
                null);
            if (summary.content() != null && !summary.content().isBlank()) {
                return summary.content().strip();
            }
        } catch (RuntimeException e) {
            log.warn("Madeleine sidekick summary failed; falling back to truncated JSON: {}",
                e.toString());
        }
        // Truthful degradation: as much of the document as fits, explicitly
        // marked as cut off rather than passed off as complete.
        return text.substring(0, maxChars) + " …[result truncated]";
    }
}
