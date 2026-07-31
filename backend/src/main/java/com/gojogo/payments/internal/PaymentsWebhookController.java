package com.gojogo.payments.internal;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

/**
 * Stripe's callback — the event that actually moves money into a wallet.
 *
 * <p>The body is taken as {@code byte[]} and not as a parsed object, because the
 * signature covers the exact bytes that were sent: re-serialising the JSON
 * changes key order or whitespace and turns every legitimate delivery into a
 * forgery. Same reason, same shape as the Sumsub webhook.
 *
 * <p>Outside the JWT chain (the caller is a machine with no Cognito account), so
 * the signature <em>is</em> the authentication. <b>With no webhook secret
 * configured this endpoint refuses everything</b> — an unverifiable payload must
 * never be able to credit a balance, and 503 is the honest answer for "this
 * environment cannot check who you are".
 */
@RestController
class PaymentsWebhookController {

    private static final Logger log = LoggerFactory.getLogger(PaymentsWebhookController.class);

    private final StripeClient stripe;
    private final PaymentsService payments;
    private final ObjectMapper json;

    PaymentsWebhookController(StripeClient stripe, PaymentsService payments, ObjectMapper json) {
        this.stripe = stripe;
        this.payments = payments;
        this.json = json;
    }

    @PostMapping(path = "/v1/payments/webhook", consumes = MediaType.ALL_VALUE)
    ResponseEntity<String> receive(@RequestBody(required = false) byte[] body,
                                   @RequestHeader(value = "Stripe-Signature", required = false)
                                   String signature) {
        if (!stripe.webhooksEnabled()) {
            log.warn("Stripe webhook received with no signing secret configured — refusing");
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body("not configured");
        }
        if (body == null || !stripe.verifySignature(body, signature)) {
            log.warn("Stripe webhook failed signature verification — refusing");
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body("bad signature");
        }

        JsonNode event;
        try {
            event = json.readTree(body);
        } catch (Exception e) {
            // Signed but unreadable should never happen; 400 rather than 500 so
            // Stripe stops retrying something that will never parse.
            log.warn("Stripe webhook body did not parse: {}", e.toString());
            return ResponseEntity.badRequest().body("unreadable");
        }

        String eventId = event.path("id").asText(null);
        String type = event.path("type").asText("");
        try {
            boolean handled = payments.process(eventId, type, event.path("data").path("object"));
            // A duplicate is a 200: anything else and Stripe keeps retrying a
            // delivery that already succeeded.
            return ResponseEntity.ok(handled ? "ok" : "duplicate");
        } catch (RuntimeException e) {
            // Nothing was claimed — the transaction rolled back — so Stripe's
            // retry will do the work. 500 is what asks for that retry.
            log.error("Stripe event {} ({}) failed: {}", eventId, type, e.toString(), e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("retry");
        }
    }
}
