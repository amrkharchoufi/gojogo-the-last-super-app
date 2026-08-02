package com.gojogo.messaging.internal;

import com.gojogo.messaging.internal.MessagingRepository.WorldProfile;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The two halves of the contacts graph that a phone network gets wrong quietly.
 *
 * <p>The first is <b>history</b>. Content is fanned out on write, so an add that
 * doesn't hand over what the author already published delivers only their
 * <em>next</em> post — and the person you just added reads as somebody who has
 * never posted, indefinitely. That is not a visible failure; it is a feed that
 * looks empty for a reason nobody can see.
 *
 * <p>The second is <b>the way back</b>. The graph is one-directional on purpose,
 * so reciprocating is its own act — but a number is still the only way in, and
 * an add is still made of one. What makes reciprocating possible is that the
 * number of somebody who <em>reached you first</em> is shown to you; nobody
 * else's ever is, and that line is what these pin.
 */
class WorldContactGraphTests {

    private static final UUID ME = UUID.randomUUID();
    private static final UUID THEM = UUID.randomUUID();

    private MessagingRepository repo;
    private WorldGraphService graph;

    @BeforeEach
    void setUp() {
        repo = mock(MessagingRepository.class);
        graph = new WorldGraphService(repo);
        when(repo.getWorldProfile(THEM)).thenReturn(Optional.of(new WorldProfile(
            THEM, "+212600000001", "Sara", null, Instant.now(), true)));
        when(repo.getAlias(any(), any())).thenReturn(Optional.empty());
    }

    /**
     * The direction the whole model turns on. Adding somebody lets *them* see
     * *your* posts — so the history goes to the person being added, not to the
     * person doing the adding. Get this backwards and an add silently hands the
     * adder a copy of somebody else's private posts.
     */
    @Test
    @DisplayName("adding somebody hands them what you had already posted")
    void addingSomebodyDeliversYourBacklogToThem() {
        when(repo.profileIdForPhone(anyString())).thenReturn(Optional.of(THEM));

        graph.addContact(ME, "+212600000001", null);

        verify(repo).addContact(ME, THEM, "+212600000001");
        verify(repo).deliverBacklog(THEM, ME);
        verify(repo, never()).deliverBacklog(ME, THEM);
    }

    @Test
    @DisplayName("dropping them takes your posts back out of their feed")
    void droppingAContactWithdrawsTheBacklog() {
        when(repo.listCircles(ME)).thenReturn(List.of());

        graph.removeContact(ME, THEM);

        verify(repo).withdrawBacklog(THEM, ME);
    }

    /**
     * The audience is the author's own contact list. It used to be everyone who
     * had added the author, which meant anybody holding your number could put
     * themselves in your audience and you had no way to remove them.
     */
    @Test
    @DisplayName("a post goes to the people you added, not the people who added you")
    void contactsAudienceIsYourOwnContactList() {
        UUID mine = UUID.randomUUID();
        when(repo.listContacts(ME)).thenReturn(List.of(
            new MessagingRepository.ContactEdge(mine, null, Instant.now())));

        assertThat(graph.resolveAudience(ME, WorldAudience.CONTACTS, null))
            .containsExactly(mine);
        verify(repo, never()).followersOf(ME);
    }

    /**
     * The load-bearing one. A profile id is not a way into somebody's graph —
     * every author id on a public post is an id, and if a number came back for
     * one of those, a stranger could add themselves to an audience meant for
     * people who have the number already.
     */
    @Test
    @DisplayName("a stranger's number is not disclosed, so they cannot be added")
    void aStrangerNumberStaysHidden() {
        when(repo.isContact(ME, THEM)).thenReturn(false);
        when(repo.isContact(THEM, ME)).thenReturn(false);
        when(repo.findDirectConversation(ME, THEM)).thenReturn(Optional.empty());

        WorldContactProfileDto seen = graph.contactProfile(ME, THEM);

        assertThat(seen.phone()).isNull();
        assertThat(seen.isContact()).isFalse();
        assertThat(seen.profile()).as("the rich half is for contacts only").isNull();
    }

    @Test
    @DisplayName("somebody who has your number gets theirs shown — that's the add back")
    void theNumberOfSomebodyWhoAddedYouIsShown() {
        when(repo.isContact(ME, THEM)).thenReturn(false);
        when(repo.isContact(THEM, ME)).thenReturn(true);

        WorldContactProfileDto seen = graph.contactProfile(ME, THEM);

        assertThat(seen.phone()).isEqualTo("+212600000001");
        assertThat(seen.isContact()).as("shown is not added").isFalse();
    }

    @Test
    @DisplayName("so does somebody who opened a thread with you")
    void soDoesSomebodyWhoOpenedAThreadWithYou() {
        when(repo.isContact(ME, THEM)).thenReturn(false);
        when(repo.isContact(THEM, ME)).thenReturn(false);
        when(repo.findDirectConversation(ME, THEM)).thenReturn(Optional.of(UUID.randomUUID()));

        assertThat(graph.contactProfile(ME, THEM).phone()).isEqualTo("+212600000001");
    }
}
