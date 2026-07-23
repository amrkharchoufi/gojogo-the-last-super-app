package com.gojogo.notifications.internal;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.ECDSASigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.security.KeyFactory;
import java.security.interfaces.ECPrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Sends activity pushes to a recipient's registered devices over APNs (HTTP/2,
 * token auth). Entirely config-gated — when the .p8 key isn't configured this
 * is a no-op, so notifications still persist and the app is unaffected.
 *
 * <p>Fire-and-forget on a small executor so it never blocks the event listener.
 * A 410 (or 400 BadDeviceToken/Unregistered) prunes the dead token.
 */
@Component
@EnableConfigurationProperties(ApnsProperties.class)
class ApnsPushSender {

    private static final Logger log = LoggerFactory.getLogger(ApnsPushSender.class);

    private final ApnsProperties props;
    private final DeviceTokenRepository tokens;
    private final ProfileApi profiles;
    private final ObjectMapper json;

    private final HttpClient http = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(10)).build();
    private final ExecutorService executor = Executors.newFixedThreadPool(2, r -> {
        Thread t = new Thread(r, "apns-push");
        t.setDaemon(true);
        return t;
    });

    private volatile ECPrivateKey signingKey;
    private volatile boolean keyBroken;
    private volatile String cachedJwt;
    private volatile Instant jwtIssuedAt = Instant.EPOCH;

    ApnsPushSender(ApnsProperties props, DeviceTokenRepository tokens,
                   ProfileApi profiles, ObjectMapper json) {
        this.props = props;
        this.tokens = tokens;
        this.profiles = profiles;
        this.json = json;
    }

    /** Best-effort push for a freshly recorded notification. */
    void notify(UUID recipientId, UUID actorId, String type, UUID postId) {
        if (!props.enabled() || keyBroken) return;
        executor.submit(() -> {
            try {
                deliver(recipientId, actorId, type, postId);
            } catch (Exception e) {
                log.debug("APNs push failed: {}", e.toString());
            }
        });
    }

    private void deliver(UUID recipientId, UUID actorId, String type, UUID postId) throws Exception {
        var devices = tokens.findByProfileId(recipientId);
        if (devices.isEmpty()) return;
        ProfileDto actor = profiles.findById(actorId).orElse(null);
        String title = actor != null
            ? (actor.displayName() != null ? actor.displayName() : "@" + actor.handle())
            : "GojoGo";
        String body = phrase(type);
        byte[] payload = payload(title, body, type, postId);
        String jwt = jwt();
        for (DeviceToken device : devices) {
            send(device, jwt, payload);
        }
    }

    private void send(DeviceToken device, String jwt, byte[] payload) {
        try {
            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create("https://" + props.host() + "/3/device/" + device.getToken()))
                .header("apns-topic", props.bundleId())
                .header("apns-push-type", "alert")
                .header("authorization", "bearer " + jwt)
                .POST(HttpRequest.BodyPublishers.ofByteArray(payload))
                .build();
            HttpResponse<String> resp = http.send(request, HttpResponse.BodyHandlers.ofString());
            int code = resp.statusCode();
            if (code == 200) {
                log.info("APNs delivered to …{}", tail(device.getToken()));
            } else if (code == 410 || (code == 400 && resp.body() != null
                    && (resp.body().contains("BadDeviceToken") || resp.body().contains("Unregistered")))) {
                log.info("APNs pruned dead token …{} ({}): {}", tail(device.getToken()), code, resp.body());
                tokens.deleteByToken(device.getToken());
            } else {
                log.info("APNs {} for token …{}: {}", code, tail(device.getToken()), resp.body());
            }
        } catch (Exception e) {
            log.warn("APNs send error: {}", e.toString());
        }
    }

    private byte[] payload(String title, String body, String type, UUID postId) throws Exception {
        Map<String, Object> alert = new LinkedHashMap<>();
        alert.put("title", title);
        alert.put("body", body);
        Map<String, Object> aps = new LinkedHashMap<>();
        aps.put("alert", alert);
        aps.put("sound", "default");
        Map<String, Object> root = new LinkedHashMap<>();
        root.put("aps", aps);
        root.put("type", type);
        if (postId != null) root.put("postId", postId.toString());
        return json.writeValueAsBytes(root);
    }

    /** ES256 provider token, reused for ~50 min (APNs allows up to 60). */
    private synchronized String jwt() throws Exception {
        if (cachedJwt != null && Duration.between(jwtIssuedAt, Instant.now()).toMinutes() < 50) {
            return cachedJwt;
        }
        SignedJWT jwt = new SignedJWT(
            new JWSHeader.Builder(JWSAlgorithm.ES256).keyID(props.keyId()).build(),
            new JWTClaimsSet.Builder().issuer(props.teamId()).issueTime(new Date()).build());
        jwt.sign(new ECDSASigner(signingKey()));
        cachedJwt = jwt.serialize();
        jwtIssuedAt = Instant.now();
        return cachedJwt;
    }

    private ECPrivateKey signingKey() throws Exception {
        if (signingKey == null) {
            byte[] der = pkcs8Der(new String(Base64.getDecoder().decode(props.keyBase64())));
            signingKey = (ECPrivateKey) KeyFactory.getInstance("EC")
                .generatePrivate(new PKCS8EncodedKeySpec(der));
        }
        return signingKey;
    }

    /** Accepts a PEM (.p8) body and returns its DER bytes. */
    private static byte[] pkcs8Der(String pem) {
        String base64 = pem
            .replace("-----BEGIN PRIVATE KEY-----", "")
            .replace("-----END PRIVATE KEY-----", "")
            .replaceAll("\\s", "");
        return Base64.getDecoder().decode(base64);
    }

    private static String phrase(String type) {
        return switch (type) {
            case "follow" -> "started following you";
            case "like" -> "liked your post";
            case "comment" -> "commented on your post";
            default -> "sent you an update";
        };
    }

    private static String tail(String token) {
        return token.length() > 6 ? token.substring(token.length() - 6) : token;
    }

    @PreDestroy
    void close() {
        executor.shutdownNow();
    }
}
