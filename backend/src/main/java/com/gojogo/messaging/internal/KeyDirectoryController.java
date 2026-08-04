package com.gojogo.messaging.internal;

import com.gojogo.messaging.internal.MessagingRepository.StoredKeyBundle;
import com.gojogo.messaging.internal.MessagingRepository.StoredOneTimePreKey;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/**
 * The E2EE key directory (Phase B — see E2EE-PLAN.md). Everything here is
 * <em>public</em> cryptographic material: the server's whole role is to hand a
 * sender the recipient's published bundle so a session can start while the
 * recipient is offline. Private keys never travel; this module could not read
 * a message if it wanted to, which is the point of the entire build.
 *
 * <p>One device per account for now: {@code deviceId} is in every path and row
 * (schema-ready, per the plan's day-one rules) but only {@code 1} is accepted,
 * so multi-device later is additive rather than a migration of rows this
 * module cannot read.
 *
 * <p>Fetching a bundle consumes a one-time prekey, which makes this the one
 * read endpoint with a write's side effect — and a drain vector: any
 * authenticated caller can empty someone's pool one fetch at a time. v1
 * accepts that (bundles still work without a one-time prekey, at the cost of
 * weaker deniability for the first message) and the client tops up via
 * {@code /count}. Rate limiting belongs at the gateway when it comes.
 */
@RestController
class KeyDirectoryController {

    private final MessagingRepository repo;
    private final CurrentProfile current;

    KeyDirectoryController(MessagingRepository repo, CurrentProfile current) {
        this.repo = repo;
        this.current = current;
    }

    record SignedPreKeyDto(int id, @NotNull String publicKey, @NotNull String signature) {}

    record PreKeyDto(int id, @NotNull String publicKey) {}

    record PublishKeysRequest(
        @NotNull Integer registrationId,
        @NotNull String identityKey,
        @NotNull @Valid SignedPreKeyDto signedPreKey,
        @NotNull @Valid SignedPreKeyDto kyberPreKey,
        List<@Valid PreKeyDto> oneTimePreKeys) {}

    record KeyBundleDto(
        int registrationId,
        int deviceId,
        String identityKey,
        SignedPreKeyDto signedPreKey,
        SignedPreKeyDto kyberPreKey,
        PreKeyDto oneTimePreKey) {}

    record PreKeyCountDto(int oneTimePreKeys) {}

    /** Publishes (or replaces) the caller's bundle; new one-time prekeys append. */
    @PutMapping("/v1/keys")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void publish(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody PublishKeysRequest req) {
        UUID me = current.require(jwt).id();
        repo.putKeyBundle(me, 1,
            new StoredKeyBundle(
                req.registrationId(), req.identityKey(),
                req.signedPreKey().id(), req.signedPreKey().publicKey(), req.signedPreKey().signature(),
                req.kyberPreKey().id(), req.kyberPreKey().publicKey(), req.kyberPreKey().signature()),
            req.oneTimePreKeys() == null ? List.of() : req.oneTimePreKeys().stream()
                .map(k -> new StoredOneTimePreKey(k.id(), k.publicKey()))
                .toList());
    }

    /** How many one-time prekeys the caller still has banked — the top-up signal. */
    @GetMapping("/v1/keys/count")
    PreKeyCountDto count(@AuthenticationPrincipal Jwt jwt) {
        return new PreKeyCountDto(repo.countOneTimePreKeys(current.require(jwt).id(), 1));
    }

    /** A recipient's bundle, consuming one one-time prekey when the pool has one. */
    @GetMapping("/v1/keys/{profileId}/{deviceId}")
    KeyBundleDto bundle(@AuthenticationPrincipal Jwt jwt,
                        @PathVariable UUID profileId, @PathVariable int deviceId) {
        current.require(jwt);
        if (deviceId != 1) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Only device 1 exists yet");
        }
        StoredKeyBundle bundle = repo.getKeyBundle(profileId, deviceId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No keys published for that account"));
        PreKeyDto oneTime = repo.consumeOneTimePreKey(profileId, deviceId)
            .map(k -> new PreKeyDto(k.id(), k.publicKey()))
            .orElse(null);
        return new KeyBundleDto(
            bundle.registrationId(), deviceId, bundle.identityKey(),
            new SignedPreKeyDto(bundle.signedPreKeyId(), bundle.signedPreKeyPublic(),
                bundle.signedPreKeySignature()),
            new SignedPreKeyDto(bundle.kyberPreKeyId(), bundle.kyberPreKeyPublic(),
                bundle.kyberPreKeySignature()),
            oneTime);
    }
}
