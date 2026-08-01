package com.gojogo.moderation.internal;

import com.gojogo.auth.AccountAdminApi;
import com.gojogo.moderation.ModeratableContent;
import com.gojogo.moderation.ModerationAction;
import com.gojogo.moderation.ModerationTargetKind;
import com.gojogo.profile.BusinessProfileDto;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import com.gojogo.profile.ProfileKind;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The decisions a moderator can and cannot make, and what each one leaves behind.
 *
 * <p>The interesting cases are all refusals: a report a queue could never close,
 * a suspension that would lock out the wrong person, and a "handled" recorded
 * over an identity provider that never heard about it.
 */
class ModerationDecisionTests {

    private static final UUID REPORTER = UUID.randomUUID();
    private static final UUID AUTHOR = UUID.randomUUID();
    private static final UUID POST = UUID.randomUUID();

    private ReportRepository reports;
    private ProfileApi profiles;
    private AccountAdminApi accounts;
    private RecordingHandler postHandler;
    private ModerationService service;

    @BeforeEach
    void setUp() {
        reports = mock(ReportRepository.class);
        profiles = mock(ProfileApi.class);
        accounts = mock(AccountAdminApi.class);
        postHandler = new RecordingHandler(ModerationTargetKind.POST,
            new ModeratableContent.ModerationTarget(AUTHOR, "a rude caption", false));

        when(reports.findByReporterIdAndTargetKindAndTargetId(any(), any(), any()))
            .thenReturn(Optional.empty());
        when(reports.saveAndFlush(any())).thenAnswer(call -> withId(call.getArgument(0)));
        when(reports.findByTargetKindAndTargetIdAndStatus(any(), any(), any()))
            .thenReturn(List.of());
        when(profiles.findByIds(any())).thenReturn(Map.of());
        when(profiles.findById(AUTHOR)).thenReturn(Optional.of(person(AUTHOR, "author")));
        when(profiles.signInSubject(AUTHOR)).thenReturn(Optional.of("sub-author"));
        when(accounts.disableSignIn(anyString())).thenReturn(true);
        when(accounts.enableSignIn(anyString())).thenReturn(true);

        service = new ModerationService(reports, profiles, accounts, List.of(postHandler));
    }

    // MARK: Filing

    @Test
    @DisplayName("reporting the same thing twice is one queue item")
    void reportingTwiceIsOneReport() {
        Report existing = withId(new Report(REPORTER, ModerationTargetKind.POST, POST, AUTHOR,
            ReportReason.SPAM, ""));
        when(reports.findByReporterIdAndTargetKindAndTargetId(
            REPORTER, ModerationTargetKind.POST, POST)).thenReturn(Optional.of(existing));

        ReportReceipt receipt = service.report(REPORTER, "POST", POST, "SPAM", null);

        assertThat(receipt.alreadyReported()).isTrue();
        assertThat(receipt.id()).isEqualTo(existing.getId());
        verify(reports, never()).saveAndFlush(any());
    }

    @Test
    @DisplayName("you cannot report your own content")
    void cannotReportYourOwn() {
        assertThatThrownBy(() -> service.report(AUTHOR, "POST", POST, "SPAM", null))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("your own");
    }

    @Test
    @DisplayName("a kind with no handler is refused by name, not filed into a queue nobody can close")
    void unhandledKindIsRefused() {
        assertThatThrownBy(() -> service.report(REPORTER, "LISTING", POST, "SCAM", null))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("LISTING");
    }

    @Test
    @DisplayName("an unknown kind is a 400 naming it, never a silent OTHER")
    void unknownKindIsRefused() {
        assertThatThrownBy(() -> service.report(REPORTER, "PODCAST", POST, "SPAM", null))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("PODCAST");
    }

    @Test
    @DisplayName("an unrecognised reason becomes OTHER rather than losing the report")
    void unknownReasonFallsBackToOther() {
        AtomicReference<Report> saved = new AtomicReference<>();
        // doAnswer, not when(...): re-stubbing a mocked method with when() calls
        // the previous answer with null arguments first.
        org.mockito.Mockito.doAnswer(call -> {
            saved.set(withId(call.getArgument(0)));
            return saved.get();
        }).when(reports).saveAndFlush(any());

        service.report(REPORTER, "POST", POST, "vibes", "it's just bad");

        assertThat(saved.get().getReason()).isEqualTo(ReportReason.OTHER);
    }

    @Test
    @DisplayName("reporting something that isn't there is a 404")
    void missingTargetIsNotFound() {
        postHandler.target = null;

        assertThatThrownBy(() -> service.report(REPORTER, "POST", POST, "SPAM", null))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("nothing there");
    }

    @Test
    @DisplayName("the owner is copied onto the report, so the queue still names somebody after a removal")
    void ownerIsCopiedOntoTheReport() {
        AtomicReference<Report> saved = new AtomicReference<>();
        // doAnswer, not when(...): re-stubbing a mocked method with when() calls
        // the previous answer with null arguments first.
        org.mockito.Mockito.doAnswer(call -> {
            saved.set(withId(call.getArgument(0)));
            return saved.get();
        }).when(reports).saveAndFlush(any());

        service.report(REPORTER, "POST", POST, "SPAM", null);

        assertThat(saved.get().getTargetOwnerId()).isEqualTo(AUTHOR);
    }

    // MARK: Deciding

    @Test
    @DisplayName("hiding reaches the vertical that owns the content")
    void hideDelegatesToTheHandler() {
        Report report = openReport();
        when(reports.findById(report.getId())).thenReturn(Optional.of(report));

        service.act(report.getId(), "HIDE", "first offence", "admin me@example.com");

        assertThat(postHandler.applied).containsExactly(ModerationAction.HIDE);
        assertThat(report.getStatus()).isEqualTo(ReportStatus.ACTIONED);
        assertThat(report.getAction()).isEqualTo(ModerationAction.HIDE);
        assertThat(report.getReviewedBy()).isEqualTo("admin me@example.com");
    }

    @Test
    @DisplayName("one decision closes every other open report against the same thing")
    void decidingClosesTheSiblings() {
        Report report = openReport();
        Report sibling = withId(new Report(UUID.randomUUID(), ModerationTargetKind.POST, POST,
            AUTHOR, ReportReason.HARASSMENT, ""));
        when(reports.findById(report.getId())).thenReturn(Optional.of(report));
        when(reports.findByTargetKindAndTargetIdAndStatus(
            ModerationTargetKind.POST, POST, ReportStatus.OPEN))
            .thenReturn(new ArrayList<>(List.of(report, sibling)));

        service.act(report.getId(), "HIDE", null, "admin");

        assertThat(sibling.getStatus()).isEqualTo(ReportStatus.ACTIONED);
        assertThat(sibling.getReviewNote()).contains(report.getId().toString());
    }

    @Test
    @DisplayName("dismissing closes only the report in front of you")
    void dismissingLeavesTheSiblingsOpen() {
        Report report = openReport();
        Report sibling = withId(new Report(UUID.randomUUID(), ModerationTargetKind.POST, POST,
            AUTHOR, ReportReason.HARASSMENT, ""));
        when(reports.findById(report.getId())).thenReturn(Optional.of(report));
        when(reports.findByTargetKindAndTargetIdAndStatus(
            ModerationTargetKind.POST, POST, ReportStatus.OPEN))
            .thenReturn(new ArrayList<>(List.of(report, sibling)));

        service.dismiss(report.getId(), "disagreement, not abuse", "admin");

        assertThat(report.getStatus()).isEqualTo(ReportStatus.DISMISSED);
        // Somebody else's complaint about the same post may be a different
        // complaint, and closing it unread would be a guess.
        assertThat(sibling.getStatus()).isEqualTo(ReportStatus.OPEN);
    }

    @Test
    @DisplayName("content already gone still closes the report rather than erroring")
    void alreadyDeletedContentStillCloses() {
        Report report = openReport();
        when(reports.findById(report.getId())).thenReturn(Optional.of(report));
        postHandler.target = null;

        service.act(report.getId(), "REMOVE", null, "admin");

        assertThat(postHandler.applied).isEmpty();
        assertThat(report.getStatus()).isEqualTo(ReportStatus.ACTIONED);
    }

    @Test
    @DisplayName("an action the vertical cannot perform is a 409, not a silent success")
    void unsupportedActionIsAConflict() {
        Report report = openReport();
        when(reports.findById(report.getId())).thenReturn(Optional.of(report));
        postHandler.refuse = "A post cannot be frobnicated";

        assertThatThrownBy(() -> service.act(report.getId(), "HIDE", null, "admin"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("frobnicated");
        assertThat(report.getStatus()).isEqualTo(ReportStatus.OPEN);
    }

    // MARK: Suspension

    @Test
    @DisplayName("suspending disables the owner's sign-in")
    void suspendDisablesSignIn() {
        Report report = openReport();
        when(reports.findById(report.getId())).thenReturn(Optional.of(report));

        service.act(report.getId(), "SUSPEND", "repeat offender", "admin");

        verify(accounts).disableSignIn("sub-author");
        // The content is untouched: a suspension is meant to be liftable, and
        // the evidence has to outlive the decision.
        assertThat(postHandler.applied).isEmpty();
    }

    @Test
    @DisplayName("restoring after a suspension lets them back in, rather than un-hiding nothing")
    void restoreAfterSuspendReEnables() {
        Report report = openReport();
        report.resolve(ReportStatus.ACTIONED, ModerationAction.SUSPEND, "admin", null);
        when(reports.findById(report.getId())).thenReturn(Optional.of(report));

        service.act(report.getId(), "RESTORE", null, "admin");

        verify(accounts).enableSignIn("sub-author");
        assertThat(postHandler.applied).isEmpty();
    }

    @Test
    @DisplayName("suspending a business names its owner instead of locking a person out sideways")
    void suspendingABusinessRefusesAndNamesTheOwner() {
        UUID business = UUID.randomUUID();
        UUID owner = UUID.randomUUID();
        Report report = withId(new Report(REPORTER, ModerationTargetKind.POST, POST, business,
            ReportReason.SPAM, ""));
        when(reports.findById(report.getId())).thenReturn(Optional.of(report));
        when(profiles.findById(business)).thenReturn(Optional.of(business(business, owner)));
        when(profiles.signInSubject(business)).thenReturn(Optional.empty());
        when(profiles.findBusiness(business)).thenReturn(Optional.of(
            new BusinessProfileDto(business, owner, "", "", null, "", "", "", null, null, null, true)));

        assertThatThrownBy(() -> service.act(report.getId(), "SUSPEND", null, "admin"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining(owner.toString());
        verify(accounts, never()).disableSignIn(anyString());
        assertThat(report.getStatus()).isEqualTo(ReportStatus.OPEN);
    }

    @Test
    @DisplayName("a suspension the identity provider refused is not recorded as handled")
    void aFailedSuspensionLeavesTheReportOpen() {
        Report report = openReport();
        when(reports.findById(report.getId())).thenReturn(Optional.of(report));
        when(accounts.disableSignIn(anyString())).thenReturn(false);

        assertThatThrownBy(() -> service.act(report.getId(), "SUSPEND", null, "admin"))
            .isInstanceOf(ResponseStatusException.class);
        // A queue that says "handled" over an account still signing in is worse
        // than a queue with an item left in it.
        assertThat(report.getStatus()).isEqualTo(ReportStatus.OPEN);
    }

    @Test
    @DisplayName("two handlers claiming one kind fails at startup, not at the first takedown")
    void duplicateHandlersFailFast() {
        ModeratableContent a = new RecordingHandler(ModerationTargetKind.POST, null);
        ModeratableContent b = new RecordingHandler(ModerationTargetKind.POST, null);

        assertThatThrownBy(() -> new ModerationService(reports, profiles, accounts, List.of(a, b)))
            .isInstanceOf(IllegalStateException.class)
            .hasMessageContaining("POST");
    }

    // --- helpers ---

    private Report openReport() {
        return withId(new Report(REPORTER, ModerationTargetKind.POST, POST, AUTHOR,
            ReportReason.HARASSMENT, "please look at this"));
    }

    private static <T> T withId(T entity) {
        try {
            var field = entity.getClass().getDeclaredField("id");
            field.setAccessible(true);
            if (field.get(entity) == null) {
                field.set(entity, UUID.randomUUID());
            }
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
        return entity;
    }

    private static ProfileDto person(UUID id, String handle) {
        return new ProfileDto(id, "sub-" + handle, handle + "@example.com", handle, handle,
            "", "Creator", null, null, Set.of(), ProfileKind.PERSON, null, false);
    }

    private static ProfileDto business(UUID id, UUID owner) {
        return new ProfileDto(id, null, null, "A Shop", "ashop", "", "Retail", null, null,
            Set.of(), ProfileKind.BUSINESS, owner, true);
    }

    /** A stand-in vertical: records what it was asked to do, and can be told to
     *  refuse or to report its content as gone. */
    private static final class RecordingHandler implements ModeratableContent {

        private final ModerationTargetKind kind;
        private ModerationTarget target;
        private String refuse;
        private final List<ModerationAction> applied = new ArrayList<>();

        RecordingHandler(ModerationTargetKind kind, ModerationTarget target) {
            this.kind = kind;
            this.target = target;
        }

        @Override
        public ModerationTargetKind kind() {
            return kind;
        }

        @Override
        public Optional<ModerationTarget> look(UUID targetId) {
            return Optional.ofNullable(target);
        }

        @Override
        public void apply(UUID targetId, ModerationAction action) {
            if (refuse != null) {
                throw new UnsupportedOperationException(refuse);
            }
            applied.add(action);
        }
    }
}
