package com.gojogo.kyc.internal;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * The only thing in this codebase that talks to Sumsub.
 *
 * <p>Every request is signed: {@code X-App-Access-Sig} is an HMAC-SHA256, keyed
 * on the secret, over the timestamp, the method, the path <em>including its
 * query string</em>, and the raw body. Getting any part of that concatenation
 * wrong produces a 401 that says nothing useful, so it is built in one place and
 * built once.
 *
 * <p>Sandbox and production share a host; the {@code sbx:} prefix on the app
 * token is the only difference, which means a misplaced credential silently
 * moves which world you are verifying people in. {@link #logConfiguration()}
 * says which one at startup for exactly that reason.
 */
@Component
@EnableConfigurationProperties(SumsubProperties.class)
class SumsubClient {

    private static final Logger log = LoggerFactory.getLogger(SumsubClient.class);

    private static final String ACCESS_TOKEN_PATH = "/resources/accessTokens/sdk";
    private static final String HMAC_ALGORITHM = "HmacSHA256";

    private final SumsubProperties props;
    private final ObjectMapper json;
    private final HttpClient http = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(10)).build();

    SumsubClient(SumsubProperties props, ObjectMapper json) {
        this.props = props;
        this.json = json;
        logConfiguration();
    }

    boolean enabled() {
        return props.enabled();
    }

    String levelName() {
        return props.levelName();
    }

    /**
     * Mints the short-lived token the mobile SDK launches with.
     *
     * <p>{@code userId} is our own profile id, which becomes Sumsub's
     * {@code externalUserId} — the join between their applicant and our person,
     * and the reason a webhook can find the right row. It is a UUID, so it never
     * needs the URL-encoding their docs warn about for emails.
     */
    String createAccessToken(UUID userId) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("userId", userId.toString());
        body.put("levelName", props.levelName());
        body.put("ttlInSecs", props.tokenTtlSeconds());
        JsonNode response = send("POST", ACCESS_TOKEN_PATH, writeJson(body));
        String token = response.path("token").asText(null);
        if (token == null || token.isBlank()) {
            log.error("Sumsub returned no access token for {}: {}", userId, response);
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                "Identity verification is unavailable right now");
        }
        return token;
    }

    /**
     * The applicant as Sumsub currently sees them, or null if they have never
     * started. This is the pull half of the integration — what
     * {@code POST /v1/kyc/refresh} runs on, and the reason a missed or
     * unconfigured webhook is a delay rather than a dead end.
     */
    SumsubVerdict fetchApplicant(UUID userId) {
        // The matrix-parameter form is Sumsub's own: /applicants/-;externalUserId=X/one.
        String path = "/resources/applicants/-;externalUserId="
            + URLEncoder.encode(userId.toString(), StandardCharsets.UTF_8) + "/one";
        JsonNode applicant = sendAllowingNotFound("GET", path, new byte[0]);
        return applicant == null ? null : SumsubVerdict.fromApplicant(applicant);
    }

    // MARK: Transport

    private JsonNode send(String method, String path, byte[] body) {
        JsonNode response = exchange(method, path, body, false);
        if (response == null) {
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                "Identity verification is unavailable right now");
        }
        return response;
    }

    /** Null on 404 — "no such applicant" is an answer, not a failure. */
    private JsonNode sendAllowingNotFound(String method, String path, byte[] body) {
        return exchange(method, path, body, true);
    }

    private JsonNode exchange(String method, String path, byte[] body, boolean notFoundIsNull) {
        if (!props.enabled()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Identity verification isn't configured on this environment");
        }
        String timestamp = String.valueOf(Instant.now().getEpochSecond());
        HttpRequest.Builder request = HttpRequest.newBuilder()
            .uri(URI.create(props.baseUrl() + path))
            .timeout(Duration.ofSeconds(20))
            .header("X-App-Token", props.appToken())
            .header("X-App-Access-Ts", timestamp)
            .header("X-App-Access-Sig", signature(timestamp, method, path, body))
            .header("Accept", "application/json");
        if (body.length > 0) {
            request.header("Content-Type", "application/json");
            request.method(method, HttpRequest.BodyPublishers.ofByteArray(body));
        } else {
            request.method(method, HttpRequest.BodyPublishers.noBody());
        }
        try {
            HttpResponse<String> response =
                http.send(request.build(), HttpResponse.BodyHandlers.ofString());
            int code = response.statusCode();
            if (code == 404 && notFoundIsNull) return null;
            if (code < 200 || code >= 300) {
                // The body carries Sumsub's description; log it, but never let
                // it reach the client — it can name internal configuration.
                log.warn("Sumsub {} {} → {}: {}", method, path, code, response.body());
                return null;
            }
            return json.readTree(response.body());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                "Identity verification is unavailable right now");
        } catch (Exception e) {
            log.warn("Sumsub {} {} failed: {}", method, path, e.toString());
            return null;
        }
    }

    /**
     * {@code HMAC-SHA256(secret, ts + METHOD + path + body)}, hex-encoded. The
     * path must be exactly what goes on the wire, query string included.
     */
    private String signature(String timestamp, String method, String path, byte[] body) {
        try {
            Mac mac = Mac.getInstance(HMAC_ALGORITHM);
            mac.init(new SecretKeySpec(
                props.secretKey().getBytes(StandardCharsets.UTF_8), HMAC_ALGORITHM));
            mac.update(timestamp.getBytes(StandardCharsets.UTF_8));
            mac.update(method.getBytes(StandardCharsets.UTF_8));
            mac.update(path.getBytes(StandardCharsets.UTF_8));
            if (body.length > 0) mac.update(body);
            return HexFormat.of().formatHex(mac.doFinal());
        } catch (Exception e) {
            throw new IllegalStateException("Could not sign the Sumsub request", e);
        }
    }

    private byte[] writeJson(Object value) {
        try {
            return json.writeValueAsBytes(value);
        } catch (Exception e) {
            throw new IllegalStateException("Could not serialise the Sumsub request", e);
        }
    }

    private void logConfiguration() {
        if (!props.enabled()) {
            log.info("Sumsub KYC is off (no app token) — identity falls back to document review");
            return;
        }
        log.info("Sumsub KYC on: {} environment, level '{}', webhooks {}",
            props.sandbox() ? "SANDBOX (verdicts are simulated)" : "production",
            props.levelName(),
            props.webhooksEnabled() ? "verified" : "OFF (pull-only via /v1/kyc/refresh)");
    }
}
