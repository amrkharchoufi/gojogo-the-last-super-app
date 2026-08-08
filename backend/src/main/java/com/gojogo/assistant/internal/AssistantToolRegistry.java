package com.gojogo.assistant.internal;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import java.io.InputStream;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * What Madeleine can be asked to do, and what class each of those things is
 * (MADELEINE.md §5).
 *
 * <p>The schemas are loaded from {@code madeleine/catalog.json} — the shipped
 * copy of the eval's catalog — rather than written out in Java, so the tool
 * definitions the model sees in production are the definitions that were
 * measured. {@code AssistantCatalogParityTests} fails the build when the two
 * diverge.
 *
 * <p><b>Two invariants are checked at startup and fail the context if broken</b>,
 * because both of them are the security model rather than a convenience:
 *
 * <ol>
 *   <li><b>No handler may be bound to a {@code WRITE_GATED} tool.</b> Not
 *       "must not be called" — must not exist. A future contributor who wires an
 *       executor to {@code place_order} gets a refusing application, not a
 *       working shortcut past the confirm card.</li>
 *   <li><b>No handler may be bound to a name the catalog does not declare.</b> A
 *       typo would otherwise register a tool with no class at all.</li>
 * </ol>
 *
 * <p>A tool is <em>offered</em> to the model only when this build can honour it:
 * a {@code READ} tool with a handler, or any {@code WRITE_GATED} tool (which
 * needs no handler — the wall is its implementation). {@code WRITE_SAFE} (M4)
 * and {@code CLIENT} (M5) are known, classified, and withheld until they work.
 * Offering a tool that errors teaches the model to distrust the catalog.
 */
@Component
class AssistantToolRegistry {

    private static final Logger log = LoggerFactory.getLogger(AssistantToolRegistry.class);
    private static final String CATALOG = "madeleine/catalog.json";

    private final Map<String, AssistantTool> byName;
    private final List<Map<String, Object>> offeredSchemas;

    AssistantToolRegistry(ObjectMapper json, AssistantReadTools readTools) {
        Map<String, AssistantToolHandler> handlers = readTools.handlers();
        Map<String, AssistantTool> tools = new LinkedHashMap<>();
        List<Map<String, Object>> offered = new ArrayList<>();

        for (JsonNode entry : readCatalog(json)) {
            AssistantToolClass toolClass =
                AssistantToolClass.valueOf(entry.path("class").asText());
            JsonNode schema = entry.path("schema");
            String name = schema.path("function").path("name").asText();
            if (name.isBlank()) {
                throw new IllegalStateException(CATALOG + " has a tool with no name");
            }
            AssistantToolHandler handler = handlers.get(name);
            if (handler != null && toolClass == AssistantToolClass.WRITE_GATED) {
                throw new IllegalStateException("Tool " + name + " is WRITE_GATED and must have "
                    + "no executor: model output may only ever create an AssistantAction "
                    + "(MADELEINE.md §5). Remove the handler rather than the check.");
            }
            Map<String, Object> schemaMap =
                json.convertValue(schema, new TypeReference<Map<String, Object>>() {
                });
            AssistantTool tool = new AssistantTool(name, toolClass, schemaMap, handler,
                readTools.carriesUserAuthoredText(name));
            tools.put(name, tool);
            if (tool.offerable()) {
                offered.add(schemaMap);
            }
        }

        List<String> unknown = handlers.keySet().stream().filter(n -> !tools.containsKey(n))
            .sorted().toList();
        if (!unknown.isEmpty()) {
            throw new IllegalStateException("Executors registered for tools " + unknown
                + " which " + CATALOG + " does not declare — an unclassified tool is an "
                + "unenforced one");
        }

        this.byName = Map.copyOf(tools);
        this.offeredSchemas = List.copyOf(offered);

        List<String> withheld = tools.values().stream().filter(t -> !t.offerable())
            .map(AssistantTool::name).sorted().toList();
        log.info("Madeleine tool registry: {} declared, {} offered, withheld until their "
            + "milestone: {}", tools.size(), offered.size(), withheld);
    }

    /** The schemas handed to the model, in catalog order. */
    List<Map<String, Object>> offeredSchemas() {
        return offeredSchemas;
    }

    Optional<AssistantTool> find(String name) {
        return Optional.ofNullable(byName.get(name));
    }

    private static Iterable<JsonNode> readCatalog(ObjectMapper json) {
        try (InputStream in = new ClassPathResource(CATALOG).getInputStream()) {
            return json.readTree(in).path("tools");
        } catch (Exception e) {
            // Without a catalog there is no classification, and without
            // classification the gated wall does not exist. Refuse to start.
            throw new IllegalStateException("Could not read " + CATALOG, e);
        }
    }
}
