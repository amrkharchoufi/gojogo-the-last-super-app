package com.gojogo.messaging.internal;

import com.gojogo.messaging.internal.MessagingRepository.ContactEdge;
import com.gojogo.messaging.internal.MessagingRepository.StoredContent;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The one-off that makes old feed copies obey the corrected audience rule.
 *
 * <p>The revoke half is the half that matters. Copies were delivered to people
 * who had added the author, under a rule that let anybody holding a number put
 * themselves in an audience; leaving those in place would mean the rule changed
 * everywhere except where the content already is.
 */
class WorldAudienceReconcilerTests {

    private static final UUID AUTHOR = UUID.randomUUID();
    /** Somebody the author actually added. */
    private static final UUID INVITED = UUID.randomUUID();
    /** Somebody who added the author — entitled under the old rule, not the new. */
    private static final UUID INTRUDER = UUID.randomUUID();

    private MessagingRepository repo;
    private WorldAudienceReconciler reconciler;

    @BeforeEach
    void setUp() {
        repo = mock(MessagingRepository.class);
        reconciler = new WorldAudienceReconciler(repo, new MessagingProperties("t", null));
        when(repo.migrationDone(anyString())).thenReturn(false);
        when(repo.listContacts(AUTHOR)).thenReturn(List.of(
            new ContactEdge(INVITED, null, Instant.now())));
    }

    private static StoredContent post(String audience, List<UUID> viewers) {
        return new StoredContent(UUID.randomUUID(), AUTHOR, "post", "hi", List.of(),
            Instant.now(), null, audience, List.of(), viewers);
    }

    @Test
    @DisplayName("a copy held by somebody the author never added is revoked")
    void revokesCopiesOutsideTheNewAudience() {
        StoredContent c = post("CONTACTS", List.of(INTRUDER));
        when(repo.scanAllAuthorContent()).thenReturn(List.of(c));

        reconciler.reconcileOnce();

        verify(repo).deleteFeedCopy(INTRUDER, c);
        verify(repo).putFeedCopy(INVITED, c);
        verify(repo).recordViewers(c, List.of(INVITED));
        verify(repo).markMigrationDone(anyString(), anyString());
    }

    @Test
    @DisplayName("a circle post is left exactly as the author addressed it")
    void leavesCirclePostsAlone() {
        when(repo.scanAllAuthorContent()).thenReturn(List.of(post("CIRCLES", List.of(INTRUDER))));

        reconciler.reconcileOnce();

        verify(repo, never()).deleteFeedCopy(any(), any());
        verify(repo, never()).putFeedCopy(any(), any());
    }

    @Test
    @DisplayName("nothing to do is nothing written — a second run is a no-op")
    void isIdempotent() {
        when(repo.scanAllAuthorContent()).thenReturn(List.of(post("CONTACTS", List.of(INVITED))));

        reconciler.reconcileOnce();

        verify(repo, never()).deleteFeedCopy(any(), any());
        verify(repo, never()).putFeedCopy(any(), any());
        verify(repo, never()).recordViewers(any(), any());
    }

    @Test
    @DisplayName("an expired story is left to its TTL")
    void skipsExpiredStories() {
        StoredContent gone = new StoredContent(UUID.randomUUID(), AUTHOR, "story", null, List.of(),
            Instant.now().minusSeconds(90_000), Instant.now().minusSeconds(3_600),
            "CONTACTS", List.of(), List.of(INTRUDER));
        when(repo.scanAllAuthorContent()).thenReturn(List.of(gone));

        reconciler.reconcileOnce();

        verify(repo, never()).deleteFeedCopy(any(), any());
    }

    @Test
    @DisplayName("it runs once — a marker already there means the work is done")
    void runsOnlyOnce() {
        when(repo.migrationDone(anyString())).thenReturn(true);

        reconciler.reconcileOnce();

        verify(repo, never()).scanAllAuthorContent();
        verify(repo, never()).markMigrationDone(anyString(), anyString());
    }

    @Test
    @DisplayName("a failure mid-pass is not recorded as finished, and never kills startup")
    void failureLeavesTheJobToBeRedone() {
        when(repo.scanAllAuthorContent()).thenThrow(new IllegalStateException("dynamo is having a day"));

        reconciler.reconcileOnce();

        verify(repo, never()).markMigrationDone(anyString(), anyString());
    }
}
