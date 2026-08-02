package com.gojogo.payments.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.payments.AccountRef;
import com.gojogo.payments.Bucket;
import com.gojogo.payments.InsufficientFundsException;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.PayoutApi;
import com.gojogo.payments.PayoutSent;
import com.gojogo.payments.WalletApi;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.server.ResponseStatusException;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.EnumSet;
import java.util.Optional;
import java.util.UUID;

/**
 * Money leaving the platform, over Stripe Connect.
 *
 * <p>Two things make this unlike every other movement in the wallet. It can fail
 * <em>after</em> the ledger says it happened, because the second half is somebody
 * else's network; and it can be refused for reasons no balance fixes, because
 * Stripe decides when a payee may be paid.
 *
 * <p>So the order is deliberate: <b>debit first, transfer second, in two
 * separate transactions.</b> A payout that paid out without debiting is money
 * gone with no record, which is unrecoverable. One that debited and failed to
 * transfer is a FAILED row and a reversing entry, which is a normal afternoon.
 * The transactions are driven explicitly through a {@link TransactionTemplate}
 * rather than by annotations, because a self-invoked {@code @Transactional}
 * method is not intercepted at all — the annotation would have quietly bought
 * nothing.
 */
@Service
class PayoutService implements PayoutApi {

    private static final Logger log = LoggerFactory.getLogger(PayoutService.class);

    private static final String MIN_KEY = "payments.payout.min.minor";
    private static final String COOLDOWN_KEY = "payments.payout.cooldown.hours";
    private static final long MIN_DEFAULT = 1_000;
    private static final long COOLDOWN_DEFAULT_HOURS = 24;

    private final LedgerService ledger;
    private final StripeClient stripe;
    private final ConfigApi config;
    private final ConnectAccountRepository connectAccounts;
    private final PayoutRepository payouts;
    private final ApplicationEventPublisher events;
    private final TransactionTemplate txn;

    PayoutService(LedgerService ledger, StripeClient stripe, ConfigApi config,
                  ConnectAccountRepository connectAccounts, PayoutRepository payouts,
                  ApplicationEventPublisher events, PlatformTransactionManager transactions) {
        this.ledger = ledger;
        this.stripe = stripe;
        this.config = config;
        this.connectAccounts = connectAccounts;
        this.payouts = payouts;
        this.events = events;
        this.txn = new TransactionTemplate(transactions);
    }

    @Override
    public boolean isConfigured() {
        return stripe.enabled();
    }

    @Override
    @Transactional(readOnly = true)
    public ConnectStatus statusOf(OwnerKind ownerKind, UUID ownerId) {
        return connectAccounts.findByOwnerKindAndOwnerId(ownerKind, ownerId)
            .map(PayoutService::describe)
            .orElseGet(ConnectStatus::none);
    }

    @Override
    @Transactional
    public String onboardingLink(OwnerKind ownerKind, UUID ownerId, String email) {
        requireStripe();
        ConnectAccount account = connectAccounts.findByOwnerKindAndOwnerId(ownerKind, ownerId)
            .orElseGet(() -> connectAccounts.save(new ConnectAccount(ownerKind, ownerId,
                stripe.createConnectedAccount(email, null, ownerId))));
        // Refresh while we're here: the payee is about to be shown a form, and
        // "what's still missing" is exactly what they want to know.
        syncFromStripe(account);
        return stripe.createAccountLink(account.getStripeAccountId());
    }

    @Override
    public PayoutResult payOut(OwnerKind ownerKind, UUID ownerId, UUID requestedBy,
                               long amountMinor) {
        requireStripe();
        ConnectAccount account = txn.execute(status -> {
            ConnectAccount found = connectAccounts.findByOwnerKindAndOwnerId(ownerKind, ownerId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.CONFLICT,
                    "Set up payouts first"));
            syncFromStripe(found);
            return found;
        });
        if (!account.isPayoutsEnabled()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                account.getRequirementsNote().isBlank()
                    ? "Stripe is still reviewing this account"
                    : "Payouts need: " + account.getRequirementsNote());
        }
        checkLimits(ownerKind, ownerId, amountMinor);

        Payout payout = txn.execute(status -> debit(ownerKind, ownerId, requestedBy, amountMinor));
        return txn.execute(status -> send(payout.getId(), account.getStripeAccountId()));
    }

    /**
     * What has already gone out. Counted off the payout rows rather than the
     * {@code PAYOUT} ledger kind, for the reason {@link PayoutApi} states: a
     * refused transfer leaves its debit entry in place and reverses it with an
     * {@code ADJUSTMENT}, so a sum over the kind would remember a payout that
     * never happened.
     */
    @Override
    @Transactional(readOnly = true)
    public long lifetimePaidOutMinor(OwnerKind ownerKind, UUID ownerId) {
        return payouts.totalMinor(ownerKind, ownerId,
            EnumSet.of(Payout.Status.REQUESTED, Payout.Status.SENT));
    }

    private void checkLimits(OwnerKind ownerKind, UUID ownerId, long amountMinor) {
        long minimum = config.number(MIN_KEY, MIN_DEFAULT);
        if (amountMinor < minimum) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "The smallest payout is " + display(minimum));
        }
        long cooldownHours = config.number(COOLDOWN_KEY, COOLDOWN_DEFAULT_HOURS);
        Optional<Payout> last = payouts.findFirstByOwnerKindAndOwnerIdAndStatusOrderByCreatedAtDesc(
            ownerKind, ownerId, Payout.Status.SENT);
        if (last.isPresent() && last.get().getCreatedAt()
                .isAfter(OffsetDateTime.now().minus(Duration.ofHours(cooldownHours)))) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "One payout every %d hours — the last one went out %s"
                    .formatted(cooldownHours, last.get().getCreatedAt().toLocalDate()));
        }
    }

    /** Ledger side. Committed before anything is sent anywhere. */
    private Payout debit(OwnerKind ownerKind, UUID ownerId, UUID requestedBy, long amountMinor) {
        Payout payout = payouts.save(
            new Payout(ownerKind, ownerId, requestedBy, amountMinor, ledger.currency()));
        try {
            WalletApi.Movement movement = ledger.post(
                AccountRef.of(ownerKind, ownerId, Bucket.AVAILABLE), AccountRef.external(),
                amountMinor, LedgerKind.PAYOUT,
                WalletApi.Reference.of("PAYOUT", payout.getId(), "Payout"),
                "payout:" + payout.getId());
            payout.debited(movement.entryId());
        } catch (InsufficientFundsException e) {
            payout.failed("Balance is " + display(e.availableMinor()));
            payouts.save(payout);
            throw e;
        }
        return payouts.save(payout);
    }

    /** Network side. A failure here reverses the debit. */
    private PayoutResult send(UUID payoutId, String stripeAccountId) {
        Payout payout = payouts.findById(payoutId).orElseThrow();
        try {
            String transferId = stripe.createTransfer(stripeAccountId, payout.getAmountMinor(),
                payout.getCurrency(), payout.getId());
            payout.sent(transferId);
            events.publishEvent(new PayoutSent(payout.getRequestedBy(), payout.getId(),
                payout.getAmountMinor(), payout.getCurrency(), OffsetDateTime.now()));
            log.info("Payout {} sent: {} {} → {}", payout.getId(), payout.getAmountMinor(),
                payout.getCurrency(), stripeAccountId);
        } catch (RuntimeException e) {
            log.warn("Payout {} failed at the provider — reversing the debit: {}",
                payout.getId(), e.toString());
            reverse(payout);
            payout.failed("The payment provider refused the transfer");
        }
        payouts.save(payout);
        return new PayoutResult(payout.getId(), payout.getAmountMinor(), payout.getCurrency(),
            payout.getStatus().name(), payout.getFailureReason());
    }

    private void reverse(Payout payout) {
        try {
            ledger.post(AccountRef.external(),
                AccountRef.of(payout.getOwnerKind(), payout.getOwnerId(), Bucket.AVAILABLE),
                payout.getAmountMinor(), LedgerKind.ADJUSTMENT,
                WalletApi.Reference.of("PAYOUT", payout.getId(), "Payout reversed"),
                "payout:" + payout.getId() + ":reversal");
        } catch (RuntimeException e) {
            // Both halves failing is the one case a human has to look at, so it
            // is logged as loudly as this codebase logs anything.
            log.error("PAYOUT {} DEBITED BUT NEITHER SENT NOR REVERSED — needs manual "
                + "reconciliation: {}", payout.getId(), e.toString());
        }
    }

    /** Refreshes the mirrored onboarding flags. Stale is fine — they are only
     *  ever a copy of what Stripe will say when the transfer is attempted. */
    private void syncFromStripe(ConnectAccount account) {
        try {
            StripeClient.ConnectedAccountState state =
                stripe.fetchAccount(account.getStripeAccountId());
            account.sync(state.detailsSubmitted(), state.payoutsEnabled(),
                state.requirementsNote());
            connectAccounts.save(account);
        } catch (RuntimeException e) {
            log.warn("Could not refresh connected account {}: {}",
                account.getStripeAccountId(), e.toString());
        }
    }

    private void requireStripe() {
        if (!stripe.enabled()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Payouts aren't switched on yet");
        }
    }

    private static ConnectStatus describe(ConnectAccount account) {
        return new ConnectStatus(true, account.getStripeAccountId(),
            account.isDetailsSubmitted(), account.isPayoutsEnabled(),
            account.getRequirementsNote());
    }

    private static String display(long minor) {
        return "%d.%02d".formatted(minor / 100, Math.abs(minor % 100));
    }
}
