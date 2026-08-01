package com.gojogo.partner.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.payments.AccountRef;
import com.gojogo.payments.Bucket;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.WalletApi;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.OffsetDateTime;

/**
 * The $30 (SPECS §4) — held in the driver's own STAKING bucket, and the fee the
 * ID check takes out of it.
 *
 * <p><strong>The stake is the applicant's money, not the platform's.</strong> It
 * moves from their AVAILABLE into their own STAKING bucket, which is the whole
 * reason {@code payments} has buckets: it is out of circulation without changing
 * hands. That is what makes handing it back on a rejection a <em>release</em>
 * rather than a refund, and what will let Phase 3 M5 pay a passenger's
 * verification reward out of it as a transfer rather than an invention.
 *
 * <p><strong>It gates submission, not approval.</strong> Staking is what funds
 * verification, so it happens before a human spends time on the application
 * rather than after — the same reasoning that put the identity check at
 * submission in 2b M6, and the same benefit: the applicant finds out while they
 * can still act.
 *
 * <p>Every movement here is idempotency-keyed off facts already on the row, so a
 * retried request, a double-tapped button and a redelivered call collapse onto
 * one movement. None of them is derived from a clock or a random.
 */
@Service
class PartnerStakeService {

    private static final Logger log = LoggerFactory.getLogger(PartnerStakeService.class);

    private final WalletApi wallet;
    private final ConfigApi config;

    PartnerStakeService(WalletApi wallet, ConfigApi config) {
        this.wallet = wallet;
        this.config = config;
    }

    /** What this kind of partner has to stake, or 0 for one that stakes nothing. */
    long requiredStakeMinor(PartnerKind kind) {
        return switch (kind) {
            case DRIVER -> Math.max(0, config.number("partner.stake.driver.minor", 3000));
            case COURIER -> Math.max(0, config.number("partner.stake.courier.minor", 3000));
            // A restaurant's commitment is a licence and a kitchen; there is
            // nothing a stake would add, and charging one would be a tax on
            // applying.
            case RESTAURANT -> 0;
        };
    }

    boolean isStakeRequired(PartnerKind kind) {
        return requiredStakeMinor(kind) > 0;
    }

    /**
     * Locks the stake.
     *
     * <p>Throws {@link com.gojogo.payments.InsufficientFundsException} when the
     * wallet won't cover it, which the global handler turns into a 402 carrying
     * the shortfall — so the app offers a top-up instead of a dead end. Nothing
     * is recorded on the application unless the money actually moved: an
     * application that believes it is staked while the ledger disagrees is the
     * one state that must not exist.
     */
    void payStake(PartnerAccount account) {
        long required = requiredStakeMinor(account.getKind());
        if (required <= 0 || account.hasLiveStake()) return;
        WalletApi.Movement movement = wallet.transfer(
            AccountRef.user(account.getUserId(), Bucket.AVAILABLE),
            AccountRef.user(account.getUserId(), Bucket.STAKING),
            required, LedgerKind.STAKE,
            WalletApi.Reference.of("PARTNER_STAKE", account.getId(),
                account.getKind().name().charAt(0)
                    + account.getKind().name().substring(1).toLowerCase() + " stake"),
            "partner:" + account.getId() + ":stake");
        account.recordStakePaid(required, OffsetDateTime.now());
        if (movement.alreadyApplied()) {
            // The row lost its record of a movement that did happen — worth a
            // line, because it means something rolled back halfway.
            log.info("Stake for application {} was already in the ledger; row re-synced",
                account.getId());
        }
    }

    /**
     * Takes the ID check's cost out of the stake, at submission.
     *
     * <p>Charged from STAKING rather than from AVAILABLE on purpose: the whole
     * point of staking is that verification is paid for out of it, and billing a
     * separate wallet would leave an applicant able to stake and then have
     * nothing to check them with.
     *
     * <p>The idempotency key is derived from what has already been charged, so
     * a retried submission collapses onto one movement while a genuine
     * resubmission — which has moved the total — gets its own.
     */
    void chargeKycFee(PartnerAccount account, boolean firstSubmission) {
        if (!account.hasLiveStake()) return;
        long fee = firstSubmission
            ? Math.max(0, config.number("partner.kyc.fee.minor", 500))
            : Math.max(0, config.number("partner.kyc.retry.fee.minor", 0));
        // A zero fee is a movement that would say nothing. Skipping it keeps the
        // ledger free of entries whose only content is that a policy is off.
        if (fee <= 0) return;
        fee = Math.min(fee, account.remainingStakeMinor());
        if (fee <= 0) return;
        wallet.transfer(
            AccountRef.user(account.getUserId(), Bucket.STAKING),
            AccountRef.platform(),
            fee, LedgerKind.FEE,
            WalletApi.Reference.of("PARTNER_KYC_FEE", account.getId(), "ID check"),
            "partner:" + account.getId() + ":kycfee:" + account.getKycFeeMinor());
        account.recordKycFeePaid(fee, OffsetDateTime.now());
    }

    /**
     * Gives back what is left of the stake.
     *
     * <p>Called on a rejection or a withdrawal — the two outcomes where somebody
     * is not going to work here and their money should not sit locked. A
     * <em>suspension</em> deliberately does not release it: the stake is what a
     * penalty and a verification reward are paid from, and handing it back at the
     * moment somebody is in trouble defeats the mechanism.
     */
    void releaseStake(PartnerAccount account) {
        long remaining = account.remainingStakeMinor();
        if (remaining <= 0) {
            // Nothing left to give back (the fees ate it), but the row should
            // still stop claiming a live stake.
            if (account.hasLiveStake()) account.recordStakeReleased(OffsetDateTime.now());
            return;
        }
        wallet.transfer(
            AccountRef.user(account.getUserId(), Bucket.STAKING),
            AccountRef.user(account.getUserId(), Bucket.AVAILABLE),
            remaining, LedgerKind.STAKE_RELEASE,
            WalletApi.Reference.of("PARTNER_STAKE", account.getId(), "Stake returned"),
            "partner:" + account.getId() + ":stake:release");
        account.recordStakeReleased(OffsetDateTime.now());
    }

    /** What the app shows on the stake page, and what a 402 would be for. */
    StakeStatus statusOf(PartnerAccount account) {
        long required = requiredStakeMinor(account.getKind());
        long available = required <= 0 ? 0
            : wallet.balancesOf(com.gojogo.payments.OwnerKind.USER, account.getUserId())
                .available();
        return new StakeStatus(required > 0, required, account.getStakeAmountMinor(),
            account.getKycFeeMinor(), account.remainingStakeMinor(),
            account.getStakePaidAt(), account.getStakeReleasedAt(),
            wallet.currency(), available, Math.max(0, required - available));
    }
}
