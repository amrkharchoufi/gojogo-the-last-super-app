package com.gojogo.assistant.internal;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

/**
 * The prompts that shipped must be the prompts that were measured.
 *
 * <p>{@code tools/madeleine-eval/prompts.py} says why this test exists, in its
 * own docstring: "a prompt kept in a Java constant and copied into an eval
 * drifts from it within a week". This is that sentence enforced.
 *
 * <p>It is not pedantry about whitespace. MADELEINE-INFERENCE.md §9 records a
 * prompt change that moved gpt-oss-120b from 17/20 to 20/20 — worth more than
 * the gap between the top two models — and, in the same session, a
 * <em>different</em> wording of the same fix that dropped qwen from 20 to 18.
 * Prompt text at this scale is load-bearing, and an untested edit to it is an
 * unmeasured change to the product's judgement about when to spend money.
 *
 * <p>Skipped when the eval directory is absent so a source-archive build still
 * works; present in the repository, so it runs in CI.
 */
class AssistantPromptParityTests {

    @Test
    @DisplayName("the brain's system prompt is prompts.py's, character for character")
    void brainPromptMatches() {
        assertMatches("BRAIN_SYSTEM", AssistantPrompts.BRAIN_SYSTEM);
    }

    @Test
    @DisplayName("the sidekick's three prompts are prompts.py's, character for character")
    void sidekickPromptsMatch() {
        assertMatches("TRIAGE", AssistantPrompts.TRIAGE);
        assertMatches("SUMMARIZE", AssistantPrompts.SUMMARIZE);
        assertMatches("TITLE", AssistantPrompts.TITLE);
    }

    private static void assertMatches(String name, String shipped) {
        String source = promptsSource();
        assumeTrue(source != null, "tools/madeleine-eval/prompts.py not present");
        assertThat(shipped)
            .as("%s — re-run tools/madeleine-eval before changing a word of this", name)
            .isEqualTo(literal(source, name));
    }

    private static String promptsSource() {
        Path path = AssistantCatalogParityTests.findUpwards(
            Path.of("tools", "madeleine-eval", "prompts.py"));
        if (path == null) {
            return null;
        }
        try {
            return Files.readString(path, StandardCharsets.UTF_8);
        } catch (Exception unreadable) {
            return null;
        }
    }

    /**
     * Resolves one Python string assignment to its value.
     *
     * <p>Two forms appear in that file and both are handled: a triple-quoted
     * block whose long lines are joined with a trailing backslash, and a
     * parenthesised run of adjacent literals. Deliberately a small hand-written
     * reader rather than an invocation of {@code python3} — a test that needs an
     * interpreter on the build machine is a test that gets deleted the first
     * time CI does not have one.
     */
    private static String literal(String source, String name) {
        Matcher triple = Pattern.compile(name + " = \"\"\"(.*?)\"\"\"", Pattern.DOTALL)
            .matcher(source);
        if (triple.find()) {
            // A backslash at end of line joins it to the next with no newline.
            return triple.group(1).replace("\\\n", "");
        }
        Matcher parenthesised = Pattern.compile(name + " = \\((.*?)\\n\\)", Pattern.DOTALL)
            .matcher(source);
        if (!parenthesised.find()) {
            throw new AssertionError("prompts.py has no assignment for " + name);
        }
        StringBuilder joined = new StringBuilder();
        Matcher pieces = Pattern.compile("\"((?:[^\"\\\\]|\\\\.)*)\"").matcher(parenthesised.group(1));
        List<String> found = new ArrayList<>();
        while (pieces.find()) {
            found.add(pieces.group(1));
        }
        if (found.isEmpty()) {
            throw new AssertionError("prompts.py's " + name + " held no string literals");
        }
        found.forEach(piece -> joined.append(unescape(piece)));
        return joined.toString();
    }

    private static String unescape(String literal) {
        StringBuilder out = new StringBuilder(literal.length());
        for (int i = 0; i < literal.length(); i++) {
            char c = literal.charAt(i);
            if (c != '\\' || i + 1 >= literal.length()) {
                out.append(c);
                continue;
            }
            char next = literal.charAt(++i);
            switch (next) {
                case 'n' -> out.append('\n');
                case 't' -> out.append('\t');
                case '\\' -> out.append('\\');
                case '"' -> out.append('"');
                default -> out.append('\\').append(next);
            }
        }
        return out.toString();
    }
}
