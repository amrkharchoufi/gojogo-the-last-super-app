package com.gojogo.profile.internal;

import com.gojogo.auth.AccountAdminApi;
import com.gojogo.config.ConfigApi;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Limit;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

/**
 * "Delete my account", which is an App Store requirement (5.1.1(v)) and, more
 * to the point, the thing somebody is owed when they want out.
 *
 * <p><b>It is a clock, not a button.</b> Asking to be deleted disables sign-in
 * immediately — from the user's side the account is gone that second — and
 * starts a grace period (config {@code moderation.deletion.grace.days}, 30)
 * before anything is destroyed. Deleting on the spot would mean a stolen phone,
 * a bad night or a mis-tap is unrecoverable, and every product that tried it
 * added the grace period afterwards.
 *
 * <p><b>What is destroyed is the person, not the content.</b> {@link
 * UserProfile#anonymize} scrubs every identifying field and clears the Cognito
 * subject; the row's id survives so their old posts, comments and messages read
 * as "Deleted user" rather than leaving holes in other people's threads.
 * Payments ledger rows are untouched — they are a financial record, and not ours
 * to erase.
 *
 * <p><b>Two honest gaps</b>, recorded here rather than discovered later:
 * <ul>
 *   <li>Because sign-in is disabled at once, cancelling within the grace period
 *       cannot be self-service — there is no session left to do it from. An
 *       operator restores it from the moderation admin surface, which is what a
 *       support request would do anyway.</li>
 *   <li>A business profile owned by the deleted person keeps existing and
 *       becomes unmanageable, since {@code actsFor} will never match a
 *       tombstoned owner again. Winding down a merchant is an operator action
 *       with orders and money in it; doing it as a side effect of a personal
 *       account deletion would be worse than leaving it.</li>
 * </ul>
 */
@Service
class AccountDeletionService {

    /** Matches the row seeded by V28; read at the call site, not cached. */
    private static final long DEFAULT_GRACE_DAYS = 30;

    /** One night's work, so a backlog can't become an hour-long transaction. */
    private static final int SWEEP_BATCH = 200;

    private static final Logger log = LoggerFactory.getLogger(AccountDeletionService.class);

    private final UserProfileRepository profiles;
    private final AccountAdminApi accounts;
    private final ConfigApi config;

    AccountDeletionService(UserProfileRepository profiles, AccountAdminApi accounts,
                           ConfigApi config) {
        this.profiles = profiles;
        this.accounts = accounts;
        this.config = config;
    }

    /**
     * Starts the clock. Idempotent: asking twice returns the same date rather
     * than restarting the grace period, so a double tap cannot quietly buy
     * somebody another thirty days.
     */
    @Transactional
    DeletionStatusResponse request(String cognitoSub, String email) {
        UserProfile profile = profiles.findByCognitoSub(cognitoSub).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "No such account"));
        if (profile.getDeletionRequestedAt() != null) {
            return status(profile);
        }
        // Disable first. If Cognito is unreachable we must not record a deletion
        // the identity provider knows nothing about — that is an account the
        // user believes is closed and which can still be signed into.
        if (!accounts.disableSignIn(cognitoSub)) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "We couldn't close your sign-in just now. Nothing was changed — please try again.");
        }
        profile.requestDeletion();
        profiles.save(profile);
        log.warn("Account {} (@{}) requested deletion; grace ends {}", profile.getId(),
            profile.getHandle(), graceEndsAt(profile));
        return status(profile);
    }

    /**
     * An operator putting somebody back — the support path the disabled session
     * makes necessary. Refused once the scrub has run, because by then there is
     * nothing left to restore and saying otherwise would be a lie.
     */
    @Transactional
    DeletionStatusResponse restore(UUID profileId, String who) {
        UserProfile profile = profiles.findById(profileId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "No such account"));
        if (profile.getAnonymizedAt() != null) {
            throw new ResponseStatusException(HttpStatus.GONE,
                "This account was already scrubbed on " + profile.getAnonymizedAt()
                    + " — there is nothing left to restore");
        }
        if (profile.getDeletionRequestedAt() == null) {
            return status(profile); // nothing to undo
        }
        String subject = profile.getCognitoSub();
        if (subject == null || !accounts.enableSignIn(subject)) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Could not re-enable sign-in — nothing was changed");
        }
        profile.cancelDeletion();
        profiles.save(profile);
        log.warn("{} restored account {} (@{})", who, profileId, profile.getHandle());
        return status(profile);
    }

    @Transactional(readOnly = true)
    DeletionStatusResponse statusOf(String cognitoSub) {
        return profiles.findByCognitoSub(cognitoSub).map(this::status).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "No such account"));
    }

    /**
     * The sweep. Returns how many it scrubbed so the job can log a number rather
     * than "done".
     */
    @Transactional
    int sweepDueDeletions() {
        OffsetDateTime cutoff = OffsetDateTime.now().minusDays(graceDays());
        List<UserProfile> due = profiles.deletionsDue(cutoff, Limit.of(SWEEP_BATCH));
        for (UserProfile profile : due) {
            UUID id = profile.getId();
            profile.anonymize(tombstoneHandle());
            profiles.save(profile);
            log.warn("Account {} anonymized after its grace period", id);
        }
        return due.size();
    }

    private DeletionStatusResponse status(UserProfile profile) {
        return new DeletionStatusResponse(
            profile.getDeletionRequestedAt() != null,
            profile.getDeletionRequestedAt(),
            graceEndsAt(profile),
            profile.getAnonymizedAt());
    }

    private OffsetDateTime graceEndsAt(UserProfile profile) {
        return profile.getDeletionRequestedAt() == null
            ? null
            : profile.getDeletionRequestedAt().plusDays(graceDays());
    }

    private long graceDays() {
        return config.number("moderation.deletion.grace.days", DEFAULT_GRACE_DAYS);
    }

    /**
     * A handle nobody could have had and nobody can take: the column is NOT NULL
     * and UNIQUE, so a tombstone still needs a value, and it should read as dead
     * to anyone who sees it in a log or a stray join.
     */
    private String tombstoneHandle() {
        byte[] noise = new byte[6];
        ThreadLocalRandom.current().nextBytes(noise);
        return "deleted_" + HexFormat.of().formatHex(noise);
    }
}
