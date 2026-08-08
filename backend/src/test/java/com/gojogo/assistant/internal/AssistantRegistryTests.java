package com.gojogo.assistant.internal;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * The registry is where MADELEINE.md §5's "enforced in the registry, not in the
 * prompt" is either true or a comment.
 *
 * <p>These tests pin the two things a future contributor could do that would
 * silently remove the wall — bind an executor to a gated tool, or bind one to a
 * name the catalog never classified — and assert that the application refuses to
 * start rather than starting with a hole. Refusing to boot is the right severity:
 * a backend that will not come up is a deploy that fails loudly, and the failure
 * this replaces is money moving without anybody being asked.
 */
class AssistantRegistryTests {

    private static final ObjectMapper JSON = new ObjectMapper();

    @Test
    @DisplayName("an executor bound to a WRITE_GATED tool refuses to start")
    void gatedToolWithAnExecutorIsRejected() {
        AssistantReadTools tools = toolsExposing(Map.of(
            "place_order", (context, args) -> Map.of("orderId", "definitely-not")));

        assertThatThrownBy(() -> new AssistantToolRegistry(JSON, tools))
            .isInstanceOf(IllegalStateException.class)
            .hasMessageContaining("place_order")
            .hasMessageContaining("WRITE_GATED");
    }

    @Test
    @DisplayName("an executor for a tool the catalog does not declare refuses to start")
    void unclassifiedToolIsRejected() {
        AssistantReadTools tools = toolsExposing(Map.of(
            "transfer_all_my_money", (context, args) -> Map.of("done", true)));

        assertThatThrownBy(() -> new AssistantToolRegistry(JSON, tools))
            .isInstanceOf(IllegalStateException.class)
            .hasMessageContaining("transfer_all_my_money");
    }

    @Test
    @DisplayName("gated tools are offered to the model, and have no executor behind them")
    void gatedToolsAreOfferedButNotRunnable() {
        AssistantToolRegistry registry = new AssistantToolRegistry(JSON, realReadTools());

        AssistantTool placeOrder = registry.find("place_order").orElseThrow();
        assertThat(placeOrder.toolClass()).isEqualTo(AssistantToolClass.WRITE_GATED);
        // Offered, because the model has to be able to *ask* — that is what
        // raises the confirm card. Unrunnable, because asking is all it can do.
        assertThat(placeOrder.offerable()).isTrue();
        assertThat(placeOrder.handler())
            .as("a gated tool with a handler is a gated tool with a bypass")
            .isNull();
    }

    @Test
    @DisplayName("only tools this build can honour are offered to the model")
    void unimplementedToolsAreWithheld() {
        AssistantToolRegistry registry = new AssistantToolRegistry(JSON, realReadTools());

        assertThat(registry.find("build_cart").orElseThrow().offerable())
            .as("WRITE_SAFE lands with M4; offering a tool that errors teaches the "
                + "model to distrust the catalog")
            .isFalse();
        assertThat(registry.find("navigate_to").orElseThrow().offerable())
            .as("CLIENT lands with M5")
            .isFalse();

        assertThat(names(registry)).containsExactlyInAnyOrder(
            // The ten READ tools, each with an executor behind it…
            "search_all", "get_profile", "search_restaurants", "get_menu", "quote_ride",
            "get_ride_status", "get_wallet", "search_listings", "get_listing",
            "get_my_bookings",
            // …and the five gated ones, which need none.
            "place_order", "request_ride", "publish_listing", "publish_post", "book_service");
    }

    private static java.util.List<String> names(AssistantToolRegistry registry) {
        return registry.offeredSchemas().stream()
            .map(schema -> {
                @SuppressWarnings("unchecked")
                Map<String, Object> function = (Map<String, Object>) schema.get("function");
                return String.valueOf(function.get("name"));
            })
            .toList();
    }

    /**
     * The real handler names, with the real bodies replaced. What is under test
     * is the registry's classification, not what a search returns — and wiring
     * eight facades to assert that {@code place_order} has no executor would be
     * a slower test of nothing extra.
     */
    private static AssistantReadTools realReadTools() {
        Map<String, AssistantToolHandler> handlers = new LinkedHashMap<>();
        for (String name : new String[] {"search_all", "get_profile", "search_restaurants",
            "get_menu", "quote_ride", "get_ride_status", "get_wallet", "search_listings",
            "get_listing", "get_my_bookings"}) {
            handlers.put(name, (context, args) -> Map.of());
        }
        return toolsExposing(handlers);
    }

    private static AssistantReadTools toolsExposing(Map<String, AssistantToolHandler> handlers) {
        AssistantReadTools tools = mock(AssistantReadTools.class);
        when(tools.handlers()).thenReturn(handlers);
        return tools;
    }
}
