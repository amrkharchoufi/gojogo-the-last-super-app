package com.gojogo.share.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.share.ShareApi;
import com.gojogo.share.ShareableResource;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Minting, resolving and killing public links.
 *
 * <p>Two decisions carry most of the weight here.
 *
 * <p><strong>The secret is the whole security model</strong>, because the people
 * a trip is shared with are exactly the people who have no account. So it is 192
 * bits from {@link SecureRandom}, URL-safe, and never derived from the thing it
 * points at — a token you could compute from a ride id would let anybody who
 * ever saw one watch every trip in the city.
 *
 * <p><strong>Nothing is rendered at mint time.</strong> Resolving asks the
 * owning module for the payload on every read, which is what makes a tracking
 * link track. It also means a vertical that is switched off, or a build with no
 * implementation for the kind, degrades to a 404 rather than to stale data.
 */
@Service
class ShareService implements ShareApi {

    private static final SecureRandom RANDOM = new SecureRandom();
    private static final int PURGE_BATCH = 500;

    private final ShareTokenRepository tokens;
    private final ConfigApi config;
    /** Every vertical that can render a shared thing, by kind. Empty is a
     *  legitimate state — an environment with no verticals wired simply has
     *  nothing shareable. */
    private final Map<String, ShareableResource> resources;

    ShareService(ShareTokenRepository tokens, ConfigApi config,
                 List<ShareableResource> resources) {
        this.tokens = tokens;
        this.config = config;
        this.resources = resources.stream().collect(Collectors.toMap(
            r -> r.kind().toLowerCase(), Function.identity(), (a, b) -> a));
    }

    @Override
    @Transactional
    public SharedLink mint(String kind, UUID refId, UUID ownerId, ShareReason reason,
                           Duration ttl) {
        String normalised = normalise(kind);
        OffsetDateTime until = OffsetDateTime.now().plus(
            ttl == null || ttl.isNegative() || ttl.isZero() ? defaultTtl() : ttl);
        // Tapping Share twice must not scatter two secrets for one trip: the
        // second would be un-revokable by anybody already holding the first.
        Optional<ShareToken> existing = live(normalised, refId, ownerId).stream()
            .filter(t -> t.getReason() == reason)
            .findFirst();
        if (existing.isPresent()) {
            ShareToken token = existing.get();
            token.extendTo(until);
            return toLink(token);
        }
        return toLink(tokens.save(new ShareToken(freshToken(), normalised, refId, ownerId,
            reason, until)));
    }

    @Override
    @Transactional
    public void revoke(String kind, UUID refId, UUID ownerId) {
        live(normalise(kind), refId, ownerId).forEach(ShareToken::revoke);
    }

    @Override
    @Transactional(readOnly = true)
    public List<SharedLink> liveLinksFor(String kind, UUID refId, UUID ownerId) {
        return live(normalise(kind), refId, ownerId).stream().map(this::toLink).toList();
    }

    /**
     * What the public endpoint returns.
     *
     * <p>Every failure is the same 404 — expired, revoked, never existed, or a
     * kind this build cannot render. Distinguishing them would tell somebody
     * probing tokens which of their guesses was nearly right.
     */
    @Transactional
    SharedPageDto resolve(String rawToken) {
        ShareToken token = tokens.findByToken(rawToken == null ? "" : rawToken.trim())
            .filter(t -> t.isLive(OffsetDateTime.now()))
            .orElseThrow(ShareService::gone);
        ShareableResource resource = resources.get(token.getKind());
        if (resource == null) throw gone();
        ShareableResource.SharedView view = resource.render(token.getRefId())
            .orElseThrow(ShareService::gone);
        token.countView();
        return new SharedPageDto(token.getKind(), view.headline(), view.status(), view.detail(),
            view.latitude(), view.longitude(), view.etaMinutes(), view.destinationLabel(),
            view.finished(), token.getReason() == ShareReason.SOS, token.getExpiresAt());
    }

    /**
     * Drops links that stopped working a long time ago.
     *
     * <p>Deliberately long after expiry rather than at it: a link that died an
     * hour ago should tell the person holding it that the trip is over, and only
     * a row can say that. Once nobody is plausibly still looking, it is just a
     * secret sitting in a table.
     */
    @Transactional
    int purgeExpired() {
        long keepDays = Math.max(1, config.number("safety.share.purge.after.days", 30));
        List<ShareToken> stale = tokens.findByExpiresAtBefore(
            OffsetDateTime.now().minusDays(keepDays), PageRequest.of(0, PURGE_BATCH));
        tokens.deleteAll(stale);
        return stale.size();
    }

    // MARK: Helpers

    private List<ShareToken> live(String kind, UUID refId, UUID ownerId) {
        OffsetDateTime now = OffsetDateTime.now();
        return tokens.findByKindAndRefIdAndOwnerIdOrderByCreatedAtDesc(kind, refId, ownerId)
            .stream()
            .filter(t -> t.isLive(now))
            .toList();
    }

    private Duration defaultTtl() {
        return Duration.ofMinutes(Math.max(5, config.number("safety.share.ttl.minutes", 180)));
    }

    private static String normalise(String kind) {
        if (kind == null || kind.isBlank()) {
            throw new IllegalArgumentException("A share token needs a kind");
        }
        return kind.trim().toLowerCase();
    }

    /** 192 bits, URL-safe, unpadded — 32 characters. Long enough that guessing
     *  one is not a way to watch a stranger's trip. */
    private static String freshToken() {
        byte[] bytes = new byte[24];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private static ResponseStatusException gone() {
        return new ResponseStatusException(HttpStatus.NOT_FOUND,
            "This link has expired or was turned off");
    }

    private SharedLink toLink(ShareToken token) {
        String base = config.string("safety.share.base.url", "https://gojogo.app/s/");
        return new SharedLink(token.getId(), token.getToken(),
            (base.endsWith("/") ? base : base + "/") + token.getToken(),
            token.getKind(), token.getRefId(), token.getReason(), token.getExpiresAt(),
            token.getViewCount());
    }
}
