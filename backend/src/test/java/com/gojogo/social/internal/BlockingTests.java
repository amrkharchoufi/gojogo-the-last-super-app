package com.gojogo.social.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import com.gojogo.profile.ProfileKind;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * What a block actually does, pinned.
 *
 * <p>These are the invariants that make blocking mean something: it tears down
 * the relationship in the <em>same</em> transaction rather than leaving a
 * listener to catch up, it doesn't put that relationship back when the block is
 * lifted, and it refuses to be a way of finding out that somebody blocked you.
 */
class BlockingTests {

    private static final UUID ME = UUID.randomUUID();
    private static final UUID THEM = UUID.randomUUID();

    private BlockRepository blocks;
    private FollowRepository follows;
    private CloseFriendRepository closeFriends;
    private StoryMuteRepository mutes;
    private BlockService service;

    @BeforeEach
    void setUp() {
        blocks = mock(BlockRepository.class);
        follows = mock(FollowRepository.class);
        closeFriends = mock(CloseFriendRepository.class);
        mutes = mock(StoryMuteRepository.class);
        ProfileApi profiles = mock(ProfileApi.class);
        ConfigApi config = mock(ConfigApi.class);

        when(profiles.findById(THEM)).thenReturn(Optional.of(person(THEM, "them")));
        when(config.number(anyString(), anyLong())).thenAnswer(call -> call.getArgument(1));
        when(blocks.existsById(any())).thenReturn(false);
        when(blocks.countByBlockerId(any())).thenReturn(0L);

        service = new BlockService(blocks, follows, closeFriends, mutes, profiles, config);
    }

    @Test
    @DisplayName("blocking unfollows in both directions, in the same call")
    void blockingUnfollowsBothWays() {
        service.block(ME, THEM);

        verify(follows).deleteByFollowerIdAndFolloweeId(ME, THEM);
        verify(follows).deleteByFollowerIdAndFolloweeId(THEM, ME);
    }

    @Test
    @DisplayName("blocking takes each person off the other's close-friends list")
    void blockingSeversCloseFriends() {
        service.block(ME, THEM);

        verify(closeFriends).severBetween(ME, THEM);
    }

    @Test
    @DisplayName("blocking clears a story mute, which would otherwise outlive the unblock")
    void blockingClearsMutes() {
        service.block(ME, THEM);

        verify(mutes).deleteByMuterIdAndMutedId(ME, THEM);
        verify(mutes).deleteByMuterIdAndMutedId(THEM, ME);
    }

    @Test
    @DisplayName("blocking someone already blocked changes nothing")
    void blockingIsIdempotent() {
        when(blocks.existsById(new Block.Key(ME, THEM))).thenReturn(true);

        service.block(ME, THEM);

        verify(blocks, never()).saveAndFlush(any());
        verify(follows, never()).deleteByFollowerIdAndFolloweeId(any(), any());
    }

    @Test
    @DisplayName("you cannot block yourself")
    void cannotBlockYourself() {
        assertThatThrownBy(() -> service.block(ME, ME))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("yourself");
    }

    @Test
    @DisplayName("unblocking restores visibility but not the follows the block removed")
    void unblockDoesNotRefollow() {
        service.unblock(ME, THEM);

        verify(blocks).deleteByBlockerIdAndBlockedId(ME, THEM);
        verify(follows, never()).save(any());
        verify(follows, never()).saveAndFlush(any());
    }

    @Test
    @DisplayName("the block list is only what I did — never who blocked me")
    void theListIsOneDirectional() {
        when(blocks.findByBlockerIdOrderByCreatedAtDesc(ME)).thenReturn(List.of());

        assertThat(service.mine(ME)).isEmpty();
        // The reverse-direction query exists for filtering; it must never be the
        // source of a list somebody can read.
        verify(blocks, never()).blockersOf(any());
    }

    @Test
    @DisplayName("the exclusion list is padded so an empty one is still a usable 'not in'")
    void exclusionListIsNeverEmpty() {
        assertThat(BlockService.orNobody(Set.of())).containsExactly(BlockService.NOBODY);
        assertThat(BlockService.orNobody(Set.of(THEM))).contains(THEM, BlockService.NOBODY);
    }

    @Test
    @DisplayName("a conversation is refused in either direction, with the same wording")
    void theGuardRefusesEitherDirection() {
        BlockService blocking = mock(BlockService.class);
        when(blocking.hiddenFrom(ME)).thenReturn(Set.of(THEM));
        BlockConversationGuard guard = new BlockConversationGuard(blocking);

        String refusal = guard.refuseConversation(ME, List.of(ME, THEM));

        assertThat(refusal).isNotNull();
        // Nothing in the sentence says who blocked whom: being told you were
        // blocked is a reason to open a second account.
        assertThat(refusal.toLowerCase()).doesNotContain("blocked you", "you blocked");
    }

    @Test
    @DisplayName("a conversation with nobody blocked is allowed")
    void theGuardAllowsEveryoneElse() {
        BlockService blocking = mock(BlockService.class);
        when(blocking.hiddenFrom(ME)).thenReturn(Set.of());
        BlockConversationGuard guard = new BlockConversationGuard(blocking);

        assertThat(guard.refuseConversation(ME, List.of(ME, THEM))).isNull();
    }

    @Test
    @DisplayName("a group is refused if any one participant is blocked")
    void oneBlockedParticipantRefusesTheGroup() {
        UUID third = UUID.randomUUID();
        BlockService blocking = mock(BlockService.class);
        when(blocking.hiddenFrom(ME)).thenReturn(Set.of(third));
        BlockConversationGuard guard = new BlockConversationGuard(blocking);

        // Silently dropping `third` would produce a group whose membership
        // nobody agreed to.
        assertThat(guard.refuseConversation(ME, List.of(ME, THEM, third))).isNotNull();
    }

    private static ProfileDto person(UUID id, String handle) {
        return new ProfileDto(id, "sub-" + handle, handle + "@example.com", handle, handle,
            "", "Creator", null, null, Set.of(), ProfileKind.PERSON, null, false);
    }
}
