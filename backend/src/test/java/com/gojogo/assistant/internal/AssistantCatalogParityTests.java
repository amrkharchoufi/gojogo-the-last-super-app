package com.gojogo.assistant.internal;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

/**
 * The shipped tool catalog must be the measured one.
 *
 * <p>MADELEINE-INFERENCE.md §9 chose a model by running twenty scenarios against
 * {@code tools/madeleine-eval/catalog.json}. If the schemas the model is handed
 * in production drift from those — a renamed field, a widened enum, a
 * reclassified tool — then the thing that was measured is not the thing that
 * shipped, and the eval's numbers quietly stop meaning anything. Nothing would
 * fail; the results would just be about a different program.
 *
 * <p>So the two files are compared directly, and the only permitted difference
 * is the one the shipped copy makes on purpose: the eval's canned {@code stub}
 * results, which exist so the harness needs no backend and have no counterpart
 * here.
 *
 * <p>Skipped rather than failed when the eval directory is absent, so that
 * building the backend from a source archive still works. In the repository, and
 * therefore in CI, it runs.
 */
class AssistantCatalogParityTests {

    private static final ObjectMapper JSON = new ObjectMapper();

    @Test
    @DisplayName("shipped catalog matches the eval catalog, tool for tool")
    void catalogsMatch() throws Exception {
        Path evalCatalog = evalCatalog();
        assumeTrue(evalCatalog != null, "tools/madeleine-eval/catalog.json not present");

        Map<String, JsonNode> shipped = byName(shippedTools());
        Map<String, JsonNode> measured = byName(JSON.readTree(Files.readAllBytes(evalCatalog))
            .path("tools"));

        assertThat(shipped.keySet())
            .as("the shipped catalog declares exactly the tools that were measured")
            .isEqualTo(measured.keySet());

        for (Map.Entry<String, JsonNode> entry : measured.entrySet()) {
            JsonNode theirs = entry.getValue();
            JsonNode ours = shipped.get(entry.getKey());
            assertThat(ours.path("class").asText())
                .as("class of %s — this is the security model, not a label", entry.getKey())
                .isEqualTo(theirs.path("class").asText());
            assertThat(ours.path("schema"))
                .as("schema of %s — what the model is told the tool takes", entry.getKey())
                .isEqualTo(theirs.path("schema"));
        }
    }

    @Test
    @DisplayName("every gated tool in the catalog is one the executor refuses to run")
    void gatedToolsAreNamedInTheSummaries() throws Exception {
        for (JsonNode tool : shippedTools()) {
            if (!"WRITE_GATED".equals(tool.path("class").asText())) {
                continue;
            }
            String name = tool.path("schema").path("function").path("name").asText();
            // Not a security check — the wall is in the executor's switch. This
            // catches the softer failure: a gated tool nobody wrote a sentence
            // for, whose confirm card would read "Confirm this action before it
            // happens" and tell the user nothing about what they are approving.
            assertThat(AssistantActionSummaries.summaryFor(name))
                .as("confirm-card wording for %s", name)
                .isNotEqualTo("Confirm this action before it happens.");
        }
    }

    private static Iterable<JsonNode> shippedTools() throws Exception {
        try (InputStream in = new ClassPathResource("madeleine/catalog.json").getInputStream()) {
            return JSON.readTree(in).path("tools");
        }
    }

    private static Map<String, JsonNode> byName(Iterable<JsonNode> tools) {
        Map<String, JsonNode> byName = new LinkedHashMap<>();
        for (JsonNode tool : tools) {
            byName.put(tool.path("schema").path("function").path("name").asText(), tool);
        }
        return byName;
    }

    /** Walks up from the module directory looking for the eval harness. */
    static Path evalCatalog() {
        return findUpwards(Path.of("tools", "madeleine-eval", "catalog.json"));
    }

    static Path findUpwards(Path relative) {
        Path here = Path.of("").toAbsolutePath();
        while (here != null) {
            Path candidate = here.resolve(relative);
            if (Files.isRegularFile(candidate)) {
                return candidate;
            }
            here = here.getParent();
        }
        return null;
    }
}
