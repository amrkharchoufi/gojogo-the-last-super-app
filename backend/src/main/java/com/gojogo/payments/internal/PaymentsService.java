package com.gojogo.payments.internal;

import com.fasterxml.jackson.databind.JsonNode;
import com.gojogo.config.ConfigApi;
import com.gojogo.payments.AccountRef;
import com.gojogo.payments.Bucket;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.WalletApi;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * The customer's side of payments: what's in the wallet, what happened to it,
 * and how to put more in.
 *
 * <p>The one rule worth stating loudly: <strong>the wallet is credited by the
 * webhook, never by the browser coming back.</strong> A client arriving at a
 * success URL proves that a browser visited a URL — nothing more — and treating
 * that as payment is the most common way a wallet ends up funded by a payment
 * that never happened.
 */
@Service
class PaymentsService {

    private static final Logger log = LoggerFactory.getLogger(PaymentsService.class);

    private static final String TOPUP_MIN_KEY = "payments.topup.min.minor";
    private static final String TOPUP_MAX_KEY = "payments.topup.max.minor";
    private static final long TOPUP_MIN_DEFAULT = 500;
    private static final long TOPUP_MAX_DEFAULT = 50_000;

    /** How long a created-but-unpaid session stays interesting. Stripe expires
     *  its own after 24h; this is the sweep that stops a wallet screen showing
     *  a "pending" top-up from last month. */
    private static final int ABANDONED_AFTER_HOURS = 24;

    private final LedgerService ledger;
    private final TokenService tokens;
    private final StripeClient stripe;
    private final ConfigApi config;
    private final StripePaymentRepository payments;
    private final StripeEventRepository providerEvents;
    private final ConnectAccountRepository connectAccounts;

    PaymentsService(LedgerService ledger, TokenService tokens, StripeClient stripe,
                    ConfigApi config, StripePaymentRepository payments,
                    StripeEventRepository providerEvents,
                    ConnectAccountRepository connectAccounts) {
        this.ledger = ledger;
        this.tokens = tokens;
        this.stripe = stripe;
        this.config = config;
        this.payments = payments;
        this.providerEvents = providerEvents;
        this.connectAccounts = connectAccounts;
        ledger.logStartup(stripe.enabled());
    }

    @Transactional(readOnly = true)
    Dtos.WalletDto wallet(UUID userId) {
        WalletApi.Balances balances = ledger.balancesOf(OwnerKind.USER, userId);
        return new Dtos.WalletDto(balances.currency(), balances.available(), balances.escrow(),
            balances.staking(), balances.tokens(), balances.rewards(),
            stripe.enabled() && stripe.webhooksEnabled(), stripe.publishableKey(),
            config.number(TOPUP_MIN_KEY, TOPUP_MIN_DEFAULT),
            config.number(TOPUP_MAX_KEY, TOPUP_MAX_DEFAULT),
            tokens.minorPerToken());
    }

    @Transactional(readOnly = true)
    List<Dtos.TransactionDto> statement(UUID userId, int limit) {
        return ledger.statement(OwnerKind.USER, userId, limit).stream()
            .map(entry -> new Dtos.TransactionDto(entry.id(), entry.amountMinor(),
                entry.currency(), entry.kind().name(), entry.refKind(), entry.refId(),
                entry.memo(), entry.createdAt()))
            .toList();
    }

    /**
     * Starts a card top-up and returns the URL to send the customer to.
     *
     * <p>Refuses when webhooks are unconfigured even though the charge itself
     * would work: a payment this backend can take but cannot learn about is a
     * customer charged for nothing. Better to refuse before the money moves than
     * to reconcile it by hand afterwards.
     */
    @Transactional
    Dtos.TopUpResponse startTopUp(UUID userId, long amountMinor) {
        if (!stripe.enabled()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Card payments aren't switched on yet");
        }
        if (!stripe.webhooksEnabled()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Card payments are being set up — try again shortly");
        }
        long min = config.number(TOPUP_MIN_KEY, TOPUP_MIN_DEFAULT);
        long max = config.number(TOPUP_MAX_KEY, TOPUP_MAX_DEFAULT);
        if (amountMinor < min || amountMinor > max) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Top up between %s and %s".formatted(display(min), display(max)));
        }

        UUID paymentId = UUID.randomUUID();
        String currency = ledger.currency();
        StripeClient.CheckoutSession session = stripe.createTopUpSession(
            userId, paymentId, amountMinor, currency, "GoJo Wallet top-up");
        StripePayment payment = payments.save(new StripePayment(paymentId, userId,
            session.id(), session.url(), amountMinor, currency));
        return new Dtos.TopUpResponse(payment.getId(), session.url(), amountMinor, currency);
    }

    @Transactional(readOnly = true)
    List<Dtos.TopUpDto> recentTopUps(UUID userId, int limit) {
        return payments.findByUserIdOrderByCreatedAtDesc(userId,
                PageRequest.of(0, Math.clamp(limit, 1, 50))).stream()
            .map(row -> new Dtos.TopUpDto(row.getId(), row.getAmountMinor(), row.getCurrency(),
                row.getStatus().name(), row.getCheckoutUrl(), row.getCreatedAt()))
            .toList();
    }

    /**
     * The reconciliation pull, for a top-up whose webhook never arrived —
     * the same shape as KYC's {@code /refresh}, and there for the same reason:
     * an integration that only works when someone else's console is configured
     * correctly is an integration that fails silently.
     */
    @Transactional
    Dtos.TopUpDto reconcile(UUID userId, UUID paymentId) {
        StripePayment payment = payments.findById(paymentId)
            .filter(row -> row.getUserId().equals(userId))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such top-up"));
        if (payment.isPending() && stripe.enabled()) {
            JsonNode session = stripe.fetchSession(payment.getSessionId());
            if ("paid".equals(session.path("payment_status").asText())) {
                credit(payment, session.path("payment_intent").asText(null));
            } else if ("expired".equals(session.path("status").asText())) {
                payment.closed(StripePayment.Status.EXPIRED);
            }
        }
        return new Dtos.TopUpDto(payment.getId(), payment.getAmountMinor(), payment.getCurrency(),
            payment.getStatus().name(), payment.getCheckoutUrl(), payment.getCreatedAt());
    }

    // MARK: Webhook

    /**
     * Handles one signed delivery, exactly once.
     *
     * <p>The claim and the work are <b>one transaction</b> on purpose. Claiming
     * first and working afterwards would mean a transient failure — a database
     * blip mid-credit — permanently consumed the event, because Stripe's retry
     * would then be dropped as a duplicate. This way a failure rolls back the
     * claim too, and the retry does the work.
     *
     * <p>The duplicate check is an existence read rather than a caught
     * duplicate-key error: a failed insert poisons the transaction the rest of
     * the handler needs.
     *
     * @return false if this delivery had already been handled
     */
    @Transactional
    boolean process(String eventId, String type, JsonNode object) {
        if (eventId == null || eventId.isBlank() || providerEvents.existsById(eventId)) {
            return false;
        }
        providerEvents.save(new StripeEvent(eventId, type));
        handle(type, object);
        return true;
    }

    private void handle(String type, JsonNode object) {
        switch (type) {
            case "checkout.session.completed", "checkout.session.async_payment_succeeded" -> {
                String sessionId = object.path("id").asText(null);
                // "paid" is the only status that means money arrived; a session
                // can complete with payment still processing (some payment
                // methods settle later), and crediting then is crediting a hope.
                if (!"paid".equals(object.path("payment_status").asText())) {
                    log.info("Stripe session {} completed but is not paid — waiting", sessionId);
                    return;
                }
                findSession(sessionId).ifPresent(payment ->
                    credit(payment, object.path("payment_intent").asText(null)));
            }
            case "checkout.session.expired" -> findSession(object.path("id").asText(null))
                .filter(StripePayment::isPending)
                .ifPresent(payment -> payment.closed(StripePayment.Status.EXPIRED));
            case "checkout.session.async_payment_failed" ->
                findSession(object.path("id").asText(null))
                    .filter(StripePayment::isPending)
                    .ifPresent(payment -> payment.closed(StripePayment.Status.FAILED));
            case "account.updated" -> syncConnectAccount(object);
            default -> log.debug("Stripe event {} ignored", type);
        }
    }

    private Optional<StripePayment> findSession(String sessionId) {
        if (sessionId == null || sessionId.isBlank()) return Optional.empty();
        Optional<StripePayment> found = payments.findBySessionId(sessionId);
        if (found.isEmpty()) {
            // Not an error worth failing the delivery over: a session created by
            // another environment sharing this Stripe account looks exactly like
            // this, and answering non-2xx would make Stripe retry it forever.
            log.info("Stripe session {} is not one of ours — ignoring", sessionId);
        }
        return found;
    }

    /** Credits the wallet exactly once, whichever path got here first. */
    private void credit(StripePayment payment, String paymentIntentId) {
        if (!payment.isPending()) return;
        WalletApi.Movement movement = ledger.post(
            AccountRef.external(),
            AccountRef.user(payment.getUserId(), Bucket.AVAILABLE),
            payment.getAmountMinor(), LedgerKind.TOPUP,
            WalletApi.Reference.of("TOPUP", payment.getId(), "Wallet top-up"),
            "topup:" + payment.getId());
        payment.succeeded(paymentIntentId, movement.entryId());
        log.info("Wallet credited {} {} for {} (top-up {})", payment.getAmountMinor(),
            payment.getCurrency(), payment.getUserId(), payment.getId());
    }

    /** Mirrors a connected account's onboarding state, so a payout can be
     *  refused with a reason rather than by failing a transfer. */
    private void syncConnectAccount(JsonNode account) {
        String stripeAccountId = account.path("id").asText(null);
        if (stripeAccountId == null) return;
        connectAccounts.findAll().stream()
            .filter(row -> stripeAccountId.equals(row.getStripeAccountId()))
            .findFirst()
            .ifPresent(row -> {
                StringBuilder note = new StringBuilder();
                account.path("requirements").path("currently_due").forEach(field ->
                    note.append(note.isEmpty() ? "" : ", ").append(field.asText()));
                row.sync(account.path("details_submitted").asBoolean(false),
                    account.path("payouts_enabled").asBoolean(false), note.toString());
            });
    }

    /** Sessions nobody ever paid, closed out so the wallet screen stays honest. */
    @Transactional
    int sweepAbandoned() {
        List<StripePayment> stale = payments.findByStatusAndCreatedAtBefore(
            StripePayment.Status.CREATED, OffsetDateTime.now().minusHours(ABANDONED_AFTER_HOURS));
        stale.forEach(payment -> payment.closed(StripePayment.Status.EXPIRED));
        return stale.size();
    }

    private static String display(long minor) {
        return "%d.%02d".formatted(minor / 100, Math.abs(minor % 100));
    }
}
