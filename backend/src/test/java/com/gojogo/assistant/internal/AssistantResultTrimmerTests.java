package com.gojogo.assistant.internal;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * MADELEINE.md §4 step 4: results are trimmed <em>before</em> entering context.
 *
 * <p>This is the line item the whole cost model rests on. §4's original estimate
 * of 30k tokens per turn was 3–7× too high precisely because trimming works; a
 * regression here would not fail anything, it would just quietly multiply the
 * bill and move MADELEINE-INFERENCE.md §6's break-even by an order of magnitude.
 */
class AssistantResultTrimmerTests {

    private final ObjectMapper json = new ObjectMapper();
    private final AssistantModelClient models = mock(AssistantModelClient.class);
    private final AssistantPolicy policy = mock(AssistantPolicy.class);
    private AssistantResultTrimmer trimmer;

    @BeforeEach
    void setUp() {
        when(policy.toolResultMaxItems()).thenReturn(8);
        when(policy.toolResultMaxChars()).thenReturn(100_000);
        trimmer = new AssistantResultTrimmer(json, models, policy);
    }

    @Test
    @DisplayName("a long list is cut to toolResultMaxItems and says that it was")
    void listsAreCapped() throws Exception {
        Object result = Map.of("listings", IntStream.range(0, 40)
            .mapToObj(i -> Map.of("id", i, "title", "Vélo " + i))
            .toList());

        var trimmed = json.readTree(trimmer.trim(result));

        assertThat(trimmed.path("listings")).hasSize(8);
        // A model told the list was cut can narrow its query; one handed the
        // first eight in silence believes it saw the whole marketplace.
        assertThat(trimmed.path("listingsTotal").asInt()).isEqualTo(40);
        assertThat(trimmed.path("listingsTruncated").asBoolean()).isTrue();
    }

    @Test
    @DisplayName("a short list is left alone and not marked truncated")
    void shortListsAreUntouched() throws Exception {
        Object result = Map.of("restaurants", List.of(Map.of("id", 1), Map.of("id", 2)));

        var trimmed = json.readTree(trimmer.trim(result));

        assertThat(trimmed.path("restaurants")).hasSize(2);
        assertThat(trimmed.has("restaurantsTruncated")).isFalse();
        verify(models, never()).chat(any(), any(), any(), any());
    }

    @Test
    @DisplayName("anything still oversized goes to the sidekick, not to the brain")
    void oversizedResultsAreSummarised() {
        when(policy.toolResultMaxChars()).thenReturn(80);
        when(models.chat(any(), any(), any(), any())).thenReturn(
            new AssistantChatResult("Two bikes, 1200 and 450 MAD.", List.of(), 40, 12, "stop"));

        String trimmed = trimmer.trim(Map.of("description", "x".repeat(500)));

        assertThat(trimmed).isEqualTo("Two bikes, 1200 and 450 MAD.");
        verify(models).chat(org.mockito.ArgumentMatchers.eq(AssistantModelRole.SIDEKICK),
            any(), any(), any());
    }

    @Test
    @DisplayName("a sidekick that is down costs detail, never the result")
    void summariserFailureDegradesTruthfully() {
        when(policy.toolResultMaxChars()).thenReturn(80);
        when(models.chat(any(), any(), any(), any()))
            .thenThrow(new AssistantModelClient.AssistantModelException("sidekick unreachable"));

        String trimmed = trimmer.trim(Map.of("description", "x".repeat(500)));

        assertThat(trimmed)
            .as("the vertical already did this work; losing it to a summariser outage "
                + "would be the expensive kind of tidy")
            .startsWith("{\"description\":\"xxx")
            .endsWith("…[result truncated]");
    }
}
