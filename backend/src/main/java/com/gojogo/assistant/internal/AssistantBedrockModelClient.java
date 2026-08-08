package com.gojogo.assistant.internal;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.http.ContentStreamProvider;
import software.amazon.awssdk.http.SdkHttpMethod;
import software.amazon.awssdk.http.SdkHttpRequest;
import software.amazon.awssdk.http.auth.aws.signer.AwsV4HttpSigner;
import software.amazon.awssdk.http.auth.spi.signer.SignedRequest;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.function.Consumer;

/**
 * {@link AssistantModelClient} over an OpenAI-compatible chat-completions
 * endpoint, authenticated with SigV4 under the Fargate task role.
 *
 * <p><b>Nothing about the provider leaks past this file.</b> That is
 * MADELEINE-INFERENCE.md §5 rule 1, and it is why the class is written against
 * a base URL and a model name rather than against Bedrock: pointing
 * {@code MODEL_BASE_URL} at a self-hosted vLLM and turning {@code sigv4} off is
 * the whole of Route B's client-side change.
 *
 * <p><b>No API key, no secret, no new deploy flag.</b> Credentials come from the
 * default provider chain, which on Fargate is the task role that already carries
 * {@code bedrock:InvokeModel}. The eval harness uses a bearer key because it
 * runs from a laptop; production deliberately does not, which is what keeps this
 * integration incapable of shipping half-configured.
 *
 * <p><b>Non-streaming, on purpose, for now.</b> The provider's {@code usage}
 * object is the only exact token count available, and MADELEINE-INFERENCE.md
 * §6's switch trigger is a money decision that deserves an exact number rather
 * than a reconstruction from deltas. It is also precisely what the eval measured,
 * so the figures this module writes are directly comparable to the ones that
 * chose the model. SSE belongs inside this class when someone has confirmed on
 * the live endpoint that usage arrives on the final chunk; the {@code prose}
 * sink is already in the interface so that change stays local.
 */
@Component
@EnableConfigurationProperties(AssistantModelProperties.class)
class AssistantBedrockModelClient implements AssistantModelClient {

    private static final Logger log = LoggerFactory.getLogger(AssistantBedrockModelClient.class);

    /**
     * Headers java.net.http refuses to let a caller set. The signature covers
     * {@code host} and {@code content-length}, and the values the client derives
     * for itself are identical to the ones that were signed — so dropping them
     * here is safe, while forwarding them throws.
     */
    private static final Set<String> RESTRICTED =
        Set.of("host", "content-length", "connection", "upgrade", "expect");

    private final AssistantModelProperties props;
    private final ObjectMapper json;
    private final HttpClient http;
    private final AwsCredentialsProvider credentials;
    private final AwsV4HttpSigner signer = AwsV4HttpSigner.create();

    AssistantBedrockModelClient(AssistantModelProperties props, ObjectMapper json) {
        this.props = props;
        this.json = json;
        this.http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();
        this.credentials = DefaultCredentialsProvider.create();
        if (!props.configured()) {
            log.warn("Madeleine model endpoint is not configured "
                + "(gojogo.assistant.model.base-url / .name) — the assistant is off");
        } else {
            log.info("Madeleine model {} at {} (sigv4={})", props.name(), props.baseUrl(),
                props.sigv4());
        }
    }

    @Override
    public String modelId(AssistantModelRole role) {
        return props.nameFor(role);
    }

    @Override
    public AssistantChatResult chat(AssistantModelRole role, List<AssistantChatMessage> messages,
                                    List<Map<String, Object>> toolSchemas, Consumer<String> prose) {
        if (!props.configured()) {
            throw new AssistantModelException("No model endpoint configured");
        }
        byte[] body = requestBody(role, messages, toolSchemas);
        String url = props.baseUrlFor(role) + "/chat/completions";

        HttpResponse<String> response;
        try {
            response = http.send(httpRequest(url, body), HttpResponse.BodyHandlers.ofString());
        } catch (IOException | InterruptedException e) {
            if (e instanceof InterruptedException) {
                Thread.currentThread().interrupt();
            }
            throw new AssistantModelException("Model call failed: " + e, e);
        }
        if (response.statusCode() / 100 != 2) {
            // The body can carry a quota or validation message worth reading in
            // a log, and carries nothing the user should ever see.
            throw new AssistantModelException("Model returned HTTP " + response.statusCode()
                + ": " + truncate(response.body()));
        }
        AssistantChatResult result = parse(response.body());
        if (prose != null && result.content() != null && !result.content().isBlank()) {
            prose.accept(result.content());
        }
        return result;
    }

    private HttpRequest httpRequest(String url, byte[] body) {
        HttpRequest.Builder builder = HttpRequest.newBuilder(URI.create(url))
            .timeout(Duration.ofSeconds(Math.max(props.timeoutSeconds(), 1)))
            .POST(HttpRequest.BodyPublishers.ofByteArray(body));
        if (!props.sigv4()) {
            builder.header("Content-Type", "application/json");
            return builder.build();
        }
        // Content-Type is deliberately NOT set above on the signed path: the
        // signer already put it in the request it hashed, so it comes back in
        // the headers copied below. Setting it here as well would send it twice
        // — HttpRequest.Builder.header() appends rather than replaces — and the
        // service would canonicalise "application/json,application/json",
        // computing a different signature from the one that was signed. The
        // failure is a flat 401 that reads exactly like a bad credential.
        sign(url, body).forEach((name, values) -> {
            if (!RESTRICTED.contains(name.toLowerCase(Locale.ROOT))) {
                values.forEach(value -> builder.header(name, value));
            }
        });
        return builder.build();
    }

    /** SigV4 over the exact bytes being sent. */
    private Map<String, List<String>> sign(String url, byte[] body) {
        SdkHttpRequest unsigned = SdkHttpRequest.builder()
            .method(SdkHttpMethod.POST)
            .uri(URI.create(url))
            .putHeader("Content-Type", "application/json")
            .build();
        try {
            SignedRequest signed = signer.sign(r -> r
                .identity(credentials.resolveCredentials())
                .request(unsigned)
                .payload(ContentStreamProvider.fromByteArray(body))
                .putProperty(AwsV4HttpSigner.SERVICE_SIGNING_NAME, props.signingName())
                .putProperty(AwsV4HttpSigner.REGION_NAME, props.region()));
            return signed.request().headers();
        } catch (RuntimeException e) {
            // No credentials on the chain is the interesting case: it means the
            // task role grant is missing, and saying so beats a 403 nobody can
            // read.
            throw new AssistantModelException("Could not sign the model request "
                + "(no AWS credentials on the default chain?): " + e, e);
        }
    }

    // MARK: The wire shape

    private byte[] requestBody(AssistantModelRole role, List<AssistantChatMessage> messages,
                               List<Map<String, Object>> toolSchemas) {
        ObjectNode root = json.createObjectNode();
        root.put("model", props.nameFor(role));
        ArrayNode array = root.putArray("messages");
        messages.forEach(m -> array.add(toWire(m)));
        if (toolSchemas != null && !toolSchemas.isEmpty()) {
            root.set("tools", json.valueToTree(toolSchemas));
            root.put("tool_choice", "auto");
        }
        root.put("max_tokens", props.maxOutputTokens());
        // Zero, the same as the eval that chose this model. A temperature the
        // harness never measured is a behaviour nobody measured.
        root.put("temperature", 0);
        try {
            return json.writeValueAsBytes(root);
        } catch (Exception e) {
            throw new AssistantModelException("Could not serialise the model request", e);
        }
    }

    private ObjectNode toWire(AssistantChatMessage message) {
        ObjectNode node = json.createObjectNode();
        node.put("role", message.role());
        node.put("content", message.content() == null ? "" : message.content());
        if (message.toolCallId() != null) {
            node.put("tool_call_id", message.toolCallId());
        }
        if (message.toolCalls() != null && !message.toolCalls().isEmpty()) {
            ArrayNode calls = node.putArray("tool_calls");
            for (AssistantToolCall call : message.toolCalls()) {
                ObjectNode wire = calls.addObject();
                wire.put("id", call.id());
                wire.put("type", "function");
                ObjectNode function = wire.putObject("function");
                function.put("name", call.name());
                function.put("arguments", call.arguments());
            }
        }
        return node;
    }

    private AssistantChatResult parse(String body) {
        JsonNode root;
        try {
            root = json.readTree(body);
        } catch (Exception e) {
            throw new AssistantModelException("Model response was not JSON", e);
        }
        JsonNode choice = root.path("choices").path(0);
        if (choice.isMissingNode()) {
            throw new AssistantModelException("Model response carried no choices: "
                + truncate(body));
        }
        JsonNode message = choice.path("message");

        List<AssistantToolCall> calls = new ArrayList<>();
        for (JsonNode call : message.path("tool_calls")) {
            JsonNode function = call.path("function");
            // Arguments stay raw. A malformed one is a measurable failure the
            // executor counts; parsing here would turn it into an exception with
            // no tool name attached to it.
            calls.add(new AssistantToolCall(
                call.path("id").asText(""),
                function.path("name").asText(""),
                function.path("arguments").isTextual()
                    ? function.path("arguments").asText()
                    : function.path("arguments").toString()));
        }

        JsonNode usage = root.path("usage");
        return new AssistantChatResult(
            message.path("content").asText(""),
            List.copyOf(calls),
            usage.path("prompt_tokens").asInt(0),
            usage.path("completion_tokens").asInt(0),
            choice.path("finish_reason").asText(""));
    }

    private static String truncate(String body) {
        if (body == null) {
            return "";
        }
        String flat = body.replaceAll("\\s+", " ");
        return flat.length() <= 300 ? flat : flat.substring(0, 300) + "…";
    }
}
