package com.gojogo.payments.internal;

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
 * The only thing in this codebase that talks to Stripe.
 *
 * <p>Hand-rolled over {@code java.net.http} rather than the vendor SDK, for the
 * same reasons {@code SumsubClient} is: the surface actually used here is five
 * calls, the wire format is form-encoded key/value pairs, and keeping it small
 * means the module has no opinion about which SDK major version the build is on.
 * What the SDK would give us that matters — webhook signature verification — is
 * fifteen lines and lives in {@link #verifySignature}.
 *
 * <p><strong>Every write carries an Idempotency-Key.</strong> Stripe honours it
 * for 24 hours, so a retried checkout creation, a retried transfer or a
 * connection that died mid-request cannot produce two charges. The keys are
 * derived from what is being paid for, never generated, for exactly the reason
 * the ledger's are.
 */
@Component
@EnableConfigurationProperties(StripeProperties.class)
class StripeClient {

    private static final Logger log = LoggerFactory.getLogger(StripeClient.class);

    private static final String HMAC_ALGORITHM = "HmacSHA256";
    /** Stripe's own recommendation: refuse a signature older than five minutes,
     *  so a captured webhook body cannot be replayed indefinitely. */
    private static final long SIGNATURE_TOLERANCE_SECONDS = 300;

    private final StripeProperties props;
    private final ObjectMapper json;
    private final HttpClient http = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(10)).build();

    StripeClient(StripeProperties props, ObjectMapper json) {
        this.props = props;
        this.json = json;
        logConfiguration();
    }

    boolean enabled() {
        return props.enabled();
    }

    boolean webhooksEnabled() {
        return props.webhooksEnabled();
    }

    String publishableKey() {
        return props.publishableKey();
    }

    // MARK: Checkout — money in

    /**
     * Creates a hosted Checkout session for a wallet top-up and returns
     * {@code (sessionId, url)}.
     *
     * <p>Hosted rather than an in-app card form on purpose: the card details
     * never touch this backend or the app, which keeps the PCI surface at zero
     * and means no card data exists anywhere in this system to leak.
     *
     * <p>{@code client_reference_id} carries our user id so that the webhook can
     * find the person without trusting anything the browser sends back.
     */
    CheckoutSession createTopUpSession(UUID userId, UUID paymentId, long amountMinor,
                                       String currency, String productName) {
        Map<String, String> form = new LinkedHashMap<>();
        form.put("mode", "payment");
        form.put("client_reference_id", userId.toString());
        form.put("metadata[paymentId]", paymentId.toString());
        form.put("metadata[userId]", userId.toString());
        // Stripe refuses a custom URL scheme here, so the trip back into the app
        // goes through a page this backend serves, which then redirects to
        // gojogo://. See PaymentsReturnController.
        form.put("success_url", props.returnBaseUrl() + "/v1/payments/return?status=success");
        form.put("cancel_url", props.returnBaseUrl() + "/v1/payments/return?status=cancelled");
        form.put("line_items[0][quantity]", "1");
        form.put("line_items[0][price_data][currency]", currency.toLowerCase());
        form.put("line_items[0][price_data][unit_amount]", String.valueOf(amountMinor));
        form.put("line_items[0][price_data][product_data][name]", productName);
        // The session id is our idempotency anchor: one row, one session, one
        // retry-safe creation.
        JsonNode response = post("/v1/checkout/sessions", form, "topup:" + paymentId);
        return new CheckoutSession(text(response, "id"), text(response, "url"));
    }

    /** What Stripe currently thinks of a session — the reconciliation path, for
     *  a webhook that never arrived. */
    JsonNode fetchSession(String sessionId) {
        return get("/v1/checkout/sessions/" + encode(sessionId));
    }

    // MARK: Connect — money out

    /** Creates an Express connected account for a payee. */
    String createConnectedAccount(String email, String country, UUID ownerId) {
        Map<String, String> form = new LinkedHashMap<>();
        form.put("type", "express");
        if (country != null && !country.isBlank()) form.put("country", country);
        if (email != null && !email.isBlank()) form.put("email", email);
        form.put("capabilities[transfers][requested]", "true");
        form.put("metadata[ownerId]", ownerId.toString());
        return text(post("/v1/accounts", form, "connect:" + ownerId), "id");
    }

    /**
     * A single-use onboarding URL. Short-lived by Stripe's design and never
     * stored: opening it authenticates the opener as the account holder.
     */
    String createAccountLink(String stripeAccountId) {
        Map<String, String> form = new LinkedHashMap<>();
        form.put("account", stripeAccountId);
        form.put("type", "account_onboarding");
        form.put("refresh_url", props.returnBaseUrl() + "/v1/payments/return?status=refresh");
        form.put("return_url", props.returnBaseUrl() + "/v1/payments/return?status=connected");
        // No idempotency key: a second call is *meant* to mint a second link —
        // the first one expires, and a payee who came back tomorrow needs a new
        // one rather than a replay of yesterday's.
        return text(post("/v1/account_links", form, null), "url");
    }

    ConnectedAccountState fetchAccount(String stripeAccountId) {
        JsonNode account = get("/v1/accounts/" + encode(stripeAccountId));
        JsonNode due = account.path("requirements").path("currently_due");
        StringBuilder note = new StringBuilder();
        due.forEach(field -> note.append(note.isEmpty() ? "" : ", ").append(field.asText()));
        return new ConnectedAccountState(
            account.path("details_submitted").asBoolean(false),
            account.path("payouts_enabled").asBoolean(false),
            note.toString());
    }

    /**
     * Sends money to a connected account. This is a platform→connected-account
     * transfer, which is what settles what a payee has earned inside the wallet;
     * Stripe then pays it on to their bank on its own schedule.
     */
    String createTransfer(String stripeAccountId, long amountMinor, String currency,
                          UUID payoutId) {
        Map<String, String> form = new LinkedHashMap<>();
        form.put("amount", String.valueOf(amountMinor));
        form.put("currency", currency.toLowerCase());
        form.put("destination", stripeAccountId);
        form.put("metadata[payoutId]", payoutId.toString());
        return text(post("/v1/transfers", form, "payout:" + payoutId), "id");
    }

    // MARK: Webhooks

    /**
     * Verifies Stripe's {@code Stripe-Signature} over the <em>raw</em> body.
     *
     * <p>Raw bytes, not a re-serialised object: the signature covers exactly
     * what was sent, and any JSON library round-trip changes key order or
     * whitespace and turns every legitimate delivery into a forgery.
     *
     * <p>The header is {@code t=<unix>,v1=<hex>[,v1=<hex>…]} — several v1
     * signatures appear while a signing secret is being rotated, and any one
     * matching is a valid delivery.
     */
    boolean verifySignature(byte[] rawBody, String signatureHeader) {
        if (!props.webhooksEnabled() || signatureHeader == null || rawBody == null) {
            return false;
        }
        String timestamp = null;
        boolean matched = false;
        for (String part : signatureHeader.split(",")) {
            String[] pair = part.trim().split("=", 2);
            if (pair.length != 2) continue;
            if ("t".equals(pair[0])) {
                timestamp = pair[1];
            }
        }
        if (timestamp == null) return false;

        long age;
        try {
            age = Math.abs(Instant.now().getEpochSecond() - Long.parseLong(timestamp));
        } catch (NumberFormatException e) {
            return false;
        }
        if (age > SIGNATURE_TOLERANCE_SECONDS) {
            log.warn("Stripe webhook signature is {}s old — refusing as a replay", age);
            return false;
        }

        String expected = hmacHex(timestamp.getBytes(StandardCharsets.UTF_8), rawBody);
        for (String part : signatureHeader.split(",")) {
            String[] pair = part.trim().split("=", 2);
            if (pair.length == 2 && "v1".equals(pair[0]) && props.digestMatches(expected, pair[1])) {
                matched = true;
            }
        }
        return matched;
    }

    /** {@code HMAC-SHA256(whsec, "<timestamp>.<raw body>")}, hex. */
    private String hmacHex(byte[] timestamp, byte[] rawBody) {
        try {
            Mac mac = Mac.getInstance(HMAC_ALGORITHM);
            mac.init(new SecretKeySpec(
                props.webhookSecret().getBytes(StandardCharsets.UTF_8), HMAC_ALGORITHM));
            mac.update(timestamp);
            mac.update((byte) '.');
            mac.update(rawBody);
            return HexFormat.of().formatHex(mac.doFinal());
        } catch (Exception e) {
            throw new IllegalStateException("Could not verify the Stripe signature", e);
        }
    }

    // MARK: Transport

    private JsonNode post(String path, Map<String, String> form, String idempotencyKey) {
        HttpRequest.Builder request = request(path)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .POST(HttpRequest.BodyPublishers.ofString(encodeForm(form)));
        if (idempotencyKey != null) {
            request.header("Idempotency-Key", idempotencyKey);
        }
        return exchange(request, "POST " + path);
    }

    private JsonNode get(String path) {
        return exchange(request(path).GET(), "GET " + path);
    }

    private HttpRequest.Builder request(String path) {
        if (!props.enabled()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Card payments aren't configured on this environment");
        }
        return HttpRequest.newBuilder()
            .uri(URI.create(props.baseUrl() + path))
            .timeout(Duration.ofSeconds(20))
            .header("Authorization", "Bearer " + props.secretKey())
            .header("Accept", "application/json");
    }

    private JsonNode exchange(HttpRequest.Builder request, String what) {
        try {
            HttpResponse<String> response =
                http.send(request.build(), HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                // Stripe's message names the exact parameter it disliked, which
                // is invaluable in a log and unwise in a response body — it can
                // describe account configuration.
                log.warn("Stripe {} → {}: {}", what, response.statusCode(), response.body());
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                    "The payment provider refused that request");
            }
            return json.readTree(response.body());
        } catch (ResponseStatusException e) {
            throw e;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                "Payments are unavailable right now");
        } catch (Exception e) {
            log.warn("Stripe {} failed: {}", what, e.toString());
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                "Payments are unavailable right now");
        }
    }

    private static String encodeForm(Map<String, String> form) {
        StringBuilder body = new StringBuilder();
        form.forEach((key, value) -> {
            if (!body.isEmpty()) body.append('&');
            body.append(encode(key)).append('=').append(encode(value));
        });
        return body.toString();
    }

    private static String encode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    private static String text(JsonNode node, String field) {
        String value = node.path(field).asText(null);
        if (value == null || value.isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                "The payment provider returned an unexpected response");
        }
        return value;
    }

    private void logConfiguration() {
        if (!props.enabled()) {
            log.info("Stripe is off (no secret key) — the wallet works, but no money "
                + "enters or leaves the platform");
            return;
        }
        log.info("Stripe on: {} mode, webhooks {}",
            props.testMode() ? "TEST (no real money moves)" : "LIVE",
            props.webhooksEnabled() ? "verified" : "OFF (top-ups refused until a secret is set)");
    }

    record CheckoutSession(String id, String url) {
    }

    record ConnectedAccountState(boolean detailsSubmitted, boolean payoutsEnabled,
                                 String requirementsNote) {
    }
}
