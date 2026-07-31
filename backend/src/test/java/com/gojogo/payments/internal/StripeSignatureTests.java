package com.gojogo.payments.internal;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.HexFormat;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The webhook signature check — the one piece of this integration that stands
 * between a forged HTTP request and a credited wallet.
 *
 * <p>No network: these build {@code Stripe-Signature} headers exactly the way
 * Stripe does and hand them to the same code the endpoint uses.
 */
class StripeSignatureTests {

    private static final String SECRET = "whsec_test_secret_value";
    private static final String BODY = """
        {"id":"evt_1","type":"checkout.session.completed",
         "data":{"object":{"id":"cs_test_1","payment_status":"paid"}}}
        """;

    private StripeClient clientWith(String webhookSecret) {
        return new StripeClient(new StripeProperties(null, "sk_test_x", webhookSecret,
            "pk_test_x", "https://api.gojogo.app", null), new ObjectMapper());
    }

    private static String header(long timestamp, String secret, String body) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            mac.update(String.valueOf(timestamp).getBytes(StandardCharsets.UTF_8));
            mac.update((byte) '.');
            mac.update(body.getBytes(StandardCharsets.UTF_8));
            return "t=" + timestamp + ",v1=" + HexFormat.of().formatHex(mac.doFinal());
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private static long now() {
        return Instant.now().getEpochSecond();
    }

    @Test
    void acceptsAGenuineDelivery() {
        assertThat(clientWith(SECRET).verifySignature(
            BODY.getBytes(StandardCharsets.UTF_8), header(now(), SECRET, BODY))).isTrue();
    }

    /**
     * The point of signing the <em>raw</em> body: a payload edited after signing
     * — the "paid" that credits a wallet, say — must not verify.
     */
    @Test
    void refusesABodyEditedAfterSigning() {
        String signature = header(now(), SECRET, BODY);
        String tampered = BODY.replace("cs_test_1", "cs_test_someone_elses");
        assertThat(clientWith(SECRET).verifySignature(
            tampered.getBytes(StandardCharsets.UTF_8), signature)).isFalse();
    }

    @Test
    void refusesTheWrongSecret() {
        assertThat(clientWith(SECRET).verifySignature(BODY.getBytes(StandardCharsets.UTF_8),
            header(now(), "whsec_not_ours", BODY))).isFalse();
    }

    /** A captured delivery replayed tomorrow is refused on age alone, even
     *  though its signature is perfectly valid. */
    @Test
    void refusesAReplayFromLastWeek() {
        long lastWeek = now() - 7 * 24 * 3600;
        assertThat(clientWith(SECRET).verifySignature(BODY.getBytes(StandardCharsets.UTF_8),
            header(lastWeek, SECRET, BODY))).isFalse();
    }

    @Test
    void refusesAMissingOrGarbledHeader() {
        StripeClient client = clientWith(SECRET);
        byte[] body = BODY.getBytes(StandardCharsets.UTF_8);
        assertThat(client.verifySignature(body, null)).isFalse();
        assertThat(client.verifySignature(body, "")).isFalse();
        assertThat(client.verifySignature(body, "v1=deadbeef")).isFalse();
        assertThat(client.verifySignature(body, "t=notanumber,v1=deadbeef")).isFalse();
    }

    /**
     * With no signing secret there is no way to tell a real delivery from a
     * forged one, so everything is refused. An unverifiable payload must never
     * be able to move money.
     */
    @Test
    void refusesEverythingWhenUnconfigured() {
        assertThat(clientWith("").verifySignature(BODY.getBytes(StandardCharsets.UTF_8),
            header(now(), SECRET, BODY))).isFalse();
    }
}
