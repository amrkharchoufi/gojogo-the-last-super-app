package com.gojogo.kyc.internal;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.util.HexFormat;
import java.util.Map;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * Where Sumsub tells us how a check went.
 *
 * <p>Unauthenticated in the JWT chain — the caller is a machine with no Cognito
 * account — so the signature <em>is</em> the authentication, and it is checked
 * before the body is parsed as anything but bytes. The digest is computed over
 * the <b>raw request body</b>: re-serialising the JSON first would change a byte
 * somewhere and fail every legitimate delivery, which is why this method takes
 * {@code byte[]} rather than a mapped type.
 *
 * <p>Unconfigured means <em>closed</em>. With no webhook secret set there is no
 * way to tell Sumsub from anyone else who found the URL, and an endpoint that
 * flips people to VERIFIED on an unverifiable say-so is worse than no endpoint:
 * this returns 503 and the pull path carries the flow instead.
 */
@RestController
class KycWebhookController {

    private static final Logger log = LoggerFactory.getLogger(KycWebhookController.class);

    /** Sumsub names its algorithm in a header; these are the ones it sends. */
    private static final Map<String, String> ALGORITHMS = Map.of(
        "HMAC_SHA1_HEX", "HmacSHA1",
        "HMAC_SHA256_HEX", "HmacSHA256",
        "HMAC_SHA512_HEX", "HmacSHA512");

    private static final String DEFAULT_ALGORITHM = "HMAC_SHA256_HEX";

    private final KycService kyc;
    private final SumsubProperties props;
    private final ObjectMapper json;

    KycWebhookController(KycService kyc, SumsubProperties props, ObjectMapper json) {
        this.kyc = kyc;
        this.props = props;
        this.json = json;
    }

    @PostMapping("/v1/kyc/webhook")
    ResponseEntity<Void> receive(@RequestBody byte[] body,
                                 @RequestHeader(name = "x-payload-digest", required = false)
                                 String digest,
                                 @RequestHeader(name = "x-payload-digest-alg", required = false)
                                 String algorithmName) {
        if (!props.webhooksEnabled()) {
            log.warn("Sumsub webhook received but no webhook secret is configured — refused");
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
        }
        String algorithm = ALGORITHMS.get(
            algorithmName == null || algorithmName.isBlank()
                ? DEFAULT_ALGORITHM : algorithmName.trim().toUpperCase());
        if (algorithm == null) {
            log.warn("Sumsub webhook named an unknown digest algorithm '{}'", algorithmName);
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        if (!props.digestMatches(hmac(algorithm, body), digest)) {
            log.warn("Sumsub webhook failed signature verification — dropped");
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        JsonNode payload;
        try {
            payload = json.readTree(body);
        } catch (Exception e) {
            // Signed by Sumsub but unreadable. Retrying it would not help.
            log.warn("Sumsub webhook body wasn't JSON: {}", e.toString());
            return ResponseEntity.ok().build();
        }
        kyc.applyWebhook(payload);
        // 200 for anything we understood, including a delivery we deliberately
        // ignored: Sumsub retries every non-2xx, and re-sending a payload we
        // already decided to drop would just repeat forever.
        return ResponseEntity.ok().build();
    }

    private String hmac(String algorithm, byte[] body) {
        try {
            Mac mac = Mac.getInstance(algorithm);
            mac.init(new SecretKeySpec(
                props.webhookSecret().getBytes(StandardCharsets.UTF_8), algorithm));
            return HexFormat.of().formatHex(mac.doFinal(body));
        } catch (Exception e) {
            throw new IllegalStateException("Could not verify the Sumsub webhook", e);
        }
    }
}
