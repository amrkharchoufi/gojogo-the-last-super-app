package com.gojogo.profile.internal;

import com.gojogo.auth.AccountAdminApi;
import com.gojogo.config.ConfigApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Limit;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
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
 * Leaving, and the two things that must never happen: an account the user
 * believes is closed that can still be signed into, and a scrub that runs before
 * its grace period.
 */
class AccountDeletionTests {

    private static final String SUB = "cognito-sub-1";

    private UserProfileRepository profiles;
    private AccountAdminApi accounts;
    private AccountDeletionService service;
    private UserProfile me;

    @BeforeEach
    void setUp() {
        profiles = mock(UserProfileRepository.class);
        accounts = mock(AccountAdminApi.class);
        ConfigApi config = mock(ConfigApi.class);
        when(config.number(anyString(), anyLong())).thenAnswer(call -> call.getArgument(1));
        when(accounts.disableSignIn(anyString())).thenReturn(true);
        when(accounts.enableSignIn(anyString())).thenReturn(true);

        me = withId(new UserProfile(SUB, "me@example.com", "me"));
        when(profiles.findByCognitoSub(SUB)).thenReturn(Optional.of(me));
        when(profiles.findById(me.getId())).thenReturn(Optional.of(me));

        service = new AccountDeletionService(profiles,
            mock(EmergencyContactRepository.class), accounts, config);
    }

    @Test
    @DisplayName("asking to be deleted disables sign-in and starts the clock")
    void requestDisablesAndRecords() {
        DeletionStatusResponse status = service.request(SUB, "me@example.com");

        verify(accounts).disableSignIn(SUB);
        assertThat(status.pending()).isTrue();
        assertThat(status.requestedAt()).isNotNull();
        assertThat(status.graceEndsAt()).isAfter(OffsetDateTime.now().plusDays(29));
        assertThat(status.anonymizedAt()).isNull();
    }

    @Test
    @DisplayName("if the identity provider can't be reached, nothing is recorded")
    void aFailedDisableRecordsNothing() {
        when(accounts.disableSignIn(anyString())).thenReturn(false);

        assertThatThrownBy(() -> service.request(SUB, "me@example.com"))
            .isInstanceOf(ResponseStatusException.class);
        // The alternative is an account the user has been told is closed and
        // which someone can still sign into.
        assertThat(me.getDeletionRequestedAt()).isNull();
        verify(profiles, never()).save(any());
    }

    @Test
    @DisplayName("asking twice does not buy another thirty days")
    void secondRequestDoesNotRestartTheClock() {
        service.request(SUB, "me@example.com");
        OffsetDateTime first = me.getDeletionRequestedAt();

        DeletionStatusResponse again = service.request(SUB, "me@example.com");

        assertThat(me.getDeletionRequestedAt()).isEqualTo(first);
        assertThat(again.requestedAt()).isEqualTo(first);
    }

    @Test
    @DisplayName("an operator can undo a deletion inside its grace period")
    void restoreCancelsThePendingDeletion() {
        service.request(SUB, "me@example.com");

        DeletionStatusResponse status = service.restore(me.getId(), "admin me@example.com");

        verify(accounts).enableSignIn(SUB);
        assertThat(status.pending()).isFalse();
        assertThat(me.getDeletionRequestedAt()).isNull();
    }

    @Test
    @DisplayName("restoring an account already scrubbed is a 410, not a lie")
    void restoreAfterAnonymizeIsGone() {
        me.requestDeletion();
        me.anonymize("deleted_abc123");

        assertThatThrownBy(() -> service.restore(me.getId(), "admin"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("scrubbed");
    }

    @Test
    @DisplayName("the sweep only takes accounts whose grace has actually run out")
    void sweepAsksForTheCutoff() {
        when(profiles.deletionsDue(any(), any(Limit.class))).thenReturn(List.of());

        service.sweepDueDeletions();

        var cutoff = org.mockito.ArgumentCaptor.forClass(OffsetDateTime.class);
        verify(profiles).deletionsDue(cutoff.capture(), any(Limit.class));
        assertThat(cutoff.getValue()).isBefore(OffsetDateTime.now().minusDays(29));
    }

    @Test
    @DisplayName("the scrub removes the person and keeps the row")
    void anonymizeScrubsEverythingIdentifying() {
        me.setDisplayName("My Real Name");
        me.setBio("hi");
        me.setAvatarUrl("https://example.com/me.jpg");
        me.setBirthYear(1990);
        me.setInterests(Set.of("cycling"));
        UUID id = me.getId();

        me.anonymize("deleted_abc123");

        assertThat(me.getId()).isEqualTo(id);          // the tombstone every post reads
        assertThat(me.getCognitoSub()).isNull();       // and the email is free to sign up again
        assertThat(me.getEmail()).isNull();
        assertThat(me.getDisplayName()).isNull();
        assertThat(me.getHandle()).isEqualTo("deleted_abc123");
        assertThat(me.getBio()).isEmpty();
        assertThat(me.getAvatarUrl()).isNull();
        assertThat(me.getBirthYear()).isNull();
        assertThat(me.getInterests()).isEmpty();
        assertThat(me.getAnonymizedAt()).isNotNull();
    }

    private static UserProfile withId(UserProfile profile) {
        try {
            var field = UserProfile.class.getDeclaredField("id");
            field.setAccessible(true);
            field.set(profile, UUID.randomUUID());
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
        return profile;
    }
}
