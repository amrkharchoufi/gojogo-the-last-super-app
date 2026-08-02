package com.gojogo.share.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.share.ShareApi;
import com.gojogo.share.ShareableResource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;

import java.lang.reflect.Field;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * Public tracking links.
 *
 * <p>The token is the whole security model — the people a trip is shared with
 * are exactly the people with no account here — so the tests that matter are
 * about what a link <em>stops</em> doing and when. Every failure has to look
 * identical from outside, because a stream of guesses that can tell "expired"
 * from "never existed" is a stream of guesses that is learning something.
 */
class ShareTokenTests {

    private static final String KIND = "ride";
    private static final UUID REF = UUID.randomUUID();
    private static final UUID OWNER = UUID.randomUUID();

    private final List<ShareToken> stored = new ArrayList<>();
    private ShareTokenRepository tokens;
    private ShareService service;
    private boolean renderable = true;

    @BeforeEach
    void setUp() {
        tokens = mock(ShareTokenRepository.class);
        ConfigApi config = mock(ConfigApi.class);
        when(config.number(anyString(), anyLong()))
            .thenAnswer(call -> call.getArgument(1, Long.class));
        when(config.string(anyString(), anyString()))
            .thenAnswer(call -> call.getArgument(1, String.class));
        when(tokens.save(any())).thenAnswer(call -> {
            ShareToken saved = call.getArgument(0);
            set(saved, "id", UUID.randomUUID());
            stored.add(saved);
            return saved;
        });
        when(tokens.findByKindAndRefIdAndOwnerIdOrderByCreatedAtDesc(anyString(), any(), any()))
            .thenAnswer(call -> stored.stream()
                .filter(t -> t.getKind().equals(call.getArgument(0)))
                .filter(t -> t.getRefId().equals(call.getArgument(1)))
                .filter(t -> t.getOwnerId().equals(call.getArgument(2)))
                .toList());
        when(tokens.findByToken(anyString())).thenAnswer(call -> stored.stream()
            .filter(t -> t.getToken().equals(call.getArgument(0)))
            .findFirst());

        ShareableResource ride = new ShareableResource() {
            @Override
            public String kind() {
                return KIND;
            }

            @Override
            public Optional<SharedView> render(UUID refId) {
                return renderable
                    ? Optional.of(new SharedView("Amina is travelling with Sara to Maarif",
                        "On the way", "White Dacia Logan · 12345-A-6", 33.5, -7.6, 8,
                        "Maarif", false))
                    : Optional.empty();
            }
        };
        service = new ShareService(tokens, config, List.of(ride));
    }

    @Test
    @DisplayName("a fresh link resolves to the payload its owner module renders")
    void resolvesToTheRenderedView() {
        ShareApi.SharedLink link = mint(Duration.ofMinutes(30));

        SharedPageDto page = service.resolve(link.token());

        assertThat(page.headline()).contains("Amina");
        assertThat(page.latitude()).isEqualTo(33.5);
        assertThat(page.sos()).isFalse();
        assertThat(link.url()).endsWith(link.token());
    }

    @Test
    @DisplayName("the payload is rendered on every read, not stored at mint time")
    void rendersOnEveryRead() {
        ShareApi.SharedLink link = mint(Duration.ofMinutes(30));
        service.resolve(link.token());

        // The trip ended between the two reads: a stored payload would still be
        // showing a car on a map.
        renderable = false;

        assertThatThrownBy(() -> service.resolve(link.token()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("404");
    }

    @Test
    @DisplayName("sharing twice hands back the same secret rather than scattering two")
    void mintingIsIdempotent() {
        ShareApi.SharedLink first = mint(Duration.ofMinutes(30));
        ShareApi.SharedLink second = mint(Duration.ofMinutes(30));

        assertThat(second.token()).isEqualTo(first.token());
        assertThat(stored).hasSize(1);
    }

    @Test
    @DisplayName("re-sharing a trip running late extends the link, never shortens it")
    void reshareExtendsOnly() {
        ShareApi.SharedLink long_ = mint(Duration.ofHours(3));
        ShareApi.SharedLink short_ = mint(Duration.ofMinutes(5));

        assertThat(short_.expiresAt()).isEqualTo(long_.expiresAt());
    }

    @Test
    @DisplayName("an SOS link is separate from a share link for the same trip")
    void sosLinkIsItsOwn() {
        ShareApi.SharedLink shared = mint(Duration.ofMinutes(30));
        ShareApi.SharedLink alarm = service.mint(KIND, REF, OWNER, ShareApi.ShareReason.SOS,
            Duration.ofMinutes(30));

        assertThat(alarm.token()).isNotEqualTo(shared.token());
        assertThat(service.resolve(alarm.token()).sos()).isTrue();
    }

    @Test
    @DisplayName("revoking kills the link from the next request")
    void revokeStopsIt() {
        ShareApi.SharedLink link = mint(Duration.ofMinutes(30));

        service.revoke(KIND, REF, OWNER);

        assertThatThrownBy(() -> service.resolve(link.token()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("404");
    }

    @Test
    @DisplayName("an expired link is a 404, exactly like one that never existed")
    void expiryAndNonsenseLookIdentical() {
        ShareApi.SharedLink link = mint(Duration.ofMinutes(30));
        set(stored.get(0), "expiresAt", java.time.OffsetDateTime.now().minusMinutes(1));

        String expired = catchMessage(link.token());
        String nonsense = catchMessage("not-a-real-token-at-all");

        assertThat(expired).isEqualTo(nonsense);
    }

    @Test
    @DisplayName("a kind nothing on the classpath can render is a 404, not a 500")
    void unknownKindIsNotFound() {
        ShareApi.SharedLink link = service.mint("order", REF, OWNER,
            ShareApi.ShareReason.SHARE, Duration.ofMinutes(30));

        assertThatThrownBy(() -> service.resolve(link.token()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("404");
    }

    @Test
    @DisplayName("opening a link is counted, so 'did anybody look' has an answer")
    void viewsAreCounted() {
        ShareApi.SharedLink link = mint(Duration.ofMinutes(30));

        service.resolve(link.token());
        service.resolve(link.token());

        assertThat(service.liveLinksFor(KIND, REF, OWNER).getFirst().viewCount()).isEqualTo(2);
    }

    @Test
    @DisplayName("two links for two trips never collide")
    void tokensAreDistinct() {
        String one = mint(Duration.ofMinutes(30)).token();
        String two = service.mint(KIND, UUID.randomUUID(), OWNER, ShareApi.ShareReason.SHARE,
            Duration.ofMinutes(30)).token();

        assertThat(one).isNotEqualTo(two).hasSize(32);
    }

    // MARK: Fixtures

    private ShareApi.SharedLink mint(Duration ttl) {
        return service.mint(KIND, REF, OWNER, ShareApi.ShareReason.SHARE, ttl);
    }

    private String catchMessage(String token) {
        try {
            service.resolve(token);
            throw new AssertionError("expected a refusal");
        } catch (ResponseStatusException e) {
            return e.getMessage();
        }
    }

    private static void set(Object target, String field, Object value) {
        try {
            Field f = target.getClass().getDeclaredField(field);
            f.setAccessible(true);
            f.set(target, value);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }
}
