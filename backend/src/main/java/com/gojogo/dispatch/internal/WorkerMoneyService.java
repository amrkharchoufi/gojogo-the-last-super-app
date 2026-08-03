package com.gojogo.dispatch.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.PayoutApi;
import com.gojogo.payments.WalletApi;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * A driver's or courier's own money: what they have earned, and how to get it
 * out.
 *
 * <p>Lives in {@code dispatch} for the reason {@link PayoutApi}'s own javadoc
 * gives — it is "called by whichever module owns the payee" — and dispatch owns
 * the worker registry, which is the only thing in this system that can prove a
 * caller is somebody the platform pays for work. {@code payments} knows what is
 * owed; it does not know who is allowed to ask for it, and teaching it would
 * mean payments learning what a courier is and depending on the module that
 * already depends on it. Exactly the shape
 * {@code delivery.MerchantMoneyService} has had since 2e M3, and the shape
 * ARCHITECTURE §10b commits to: balances and payouts on the owning module's own
 * {@code /mine} surface, with no admin-only mirror.
 *
 * <p><strong>One surface for both registries.</strong> A dual-mode person is two
 * rows in the worker table and one human with one wallet, so the question this
 * class gates on is "do you hold <em>any</em> registration", not "which one".
 * Splitting earnings by mode would invent a distinction the ledger does not
 * make — a ride fare and a delivery fee land in the same pocket, and they were
 * earned by the same pair of hands.
 */
@Service
class WorkerMoneyService {

    private static final String PAYOUT_MIN_KEY = "payments.payout.min.minor";
    private static final long PAYOUT_MIN_DEFAULT = 1_000;

    /**
     * What counts as having been paid for work.
     *
     * <p>Every ledger kind a person can be <em>credited</em> with by doing
     * something: the delivery fee and the tip on an order, a ride fare
     * (cancellation fees ride there too, and they are the driver's time), and a
     * vehicle-verification reward. Deliberately not {@code TOPUP}, which is the
     * whole point, and deliberately not {@code CAPTURE} or {@code REFUND},
     * which are a customer's money coming back rather than a worker's arriving.
     *
     * <p>A kind added to this set widens what can leave the platform, so the
     * next person to touch it should ask whether the credit represents work
     * before adding one.
     */
    private static final Set<LedgerKind> EARNED = Set.of(
        LedgerKind.COURIER_FEE, LedgerKind.TIP, LedgerKind.RIDE_FARE, LedgerKind.REWARD);

    private final WorkerRepository workers;
    private final WalletApi wallet;
    private final PayoutApi payouts;
    private final ConfigApi config;

    WorkerMoneyService(WorkerRepository workers, WalletApi wallet, PayoutApi payouts,
                       ConfigApi config) {
        this.workers = workers;
        this.wallet = wallet;
        this.payouts = payouts;
        this.config = config;
    }

    @Transactional(readOnly = true)
    WorkerWalletDto wallet(UUID me) {
        requireRegistration(me);
        WalletApi.Balances balances = wallet.balancesOf(OwnerKind.USER, me);
        PayoutApi.ConnectStatus connect = payouts.statusOf(OwnerKind.USER, me);
        long earned = wallet.totalByKind(OwnerKind.USER, me, EARNED);
        List<WorkerTransactionDto> recent = wallet
            .statement(OwnerKind.USER, me, 25).stream()
            .map(entry -> new WorkerTransactionDto(entry.id(), entry.amountMinor(),
                entry.kind().name(), entry.memo(), entry.createdAt()))
            .toList();
        return new WorkerWalletDto(balances.available(), balances.currency(),
            earned, withdrawable(me, earned),
            connect.exists(), connect.ready(), connect.requirementsNote(),
            config.number(PAYOUT_MIN_KEY, PAYOUT_MIN_DEFAULT), recent);
    }

    /**
     * A Stripe-hosted onboarding link for this worker's payouts.
     *
     * <p>Single-use and short-lived by Stripe's design, so it is minted on
     * demand and never stored: whoever opens it is treated as the account
     * holder.
     */
    @Transactional
    String onboardingLink(UUID me, String email) {
        requireRegistration(me);
        return payouts.onboardingLink(OwnerKind.USER, me, email);
    }

    /**
     * Sends earnings to the worker's connected account.
     *
     * <p>Deliberately not {@code @Transactional}, for the reason
     * {@code MerchantMoneyService.payOut} states: a payout is two transactions
     * on purpose (debit, then transfer), and wrapping it in a third would undo
     * that — a crash mid-transfer would roll the debit back and leave money that
     * may already be in flight looking as though it never left.
     */
    WorkerPayoutDto payOut(UUID me, long amountMinor) {
        requireRegistration(me);
        // Checked twice, on purpose. Here first as a courtesy — an obviously
        // over-cap ask is refused with the right sentence before a database lock
        // or a Stripe call is spent on it. And again as the guard below, run
        // inside the payout's locked debit transaction, which is the one that
        // actually holds: two simultaneous requests both pass this outer read,
        // and only the in-lock re-check — against a paid-out total that now
        // counts the sibling — can tell the second one no.
        enforceCap(me, amountMinor);
        PayoutApi.PayoutResult result = payouts.payOut(OwnerKind.USER, me, me, amountMinor,
            () -> enforceCap(me, amountMinor));
        return new WorkerPayoutDto(result.payoutId(), result.amountMinor(), result.currency(),
            result.status(), result.failureReason());
    }

    /**
     * The cap, throwing the refusal that names whichever half bit. Reads the
     * balance and the paid-out total fresh each time it is called, so that when
     * it runs as the payout's guard — inside the transaction that has just locked
     * this worker's balance row — it sees any sibling payout that committed while
     * it waited for the lock.
     */
    private void enforceCap(UUID me, long amountMinor) {
        long available = wallet.balancesOf(OwnerKind.USER, me).available();
        long withdrawable = withdrawable(me, wallet.totalByKind(OwnerKind.USER, me, EARNED));
        if (amountMinor > Math.min(available, withdrawable)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                refusal(available, withdrawable));
        }
    }

    // MARK: The cap

    /**
     * The ceiling on a withdrawal, and the decision this whole class turns on.
     *
     * <p><b>A worker is paid into their own USER {@code AVAILABLE} bucket</b> —
     * the same pocket a card top-up lands in. That is the right shape (a person
     * has one wallet, and a courier who wants to spend the evening's fees on
     * dinner should not have to move them first), but it means this endpoint is
     * the first card→bank path this platform has ever had. A payout surface over
     * a raw balance would let anybody top up with a card and withdraw to a bank
     * account, which is money transmission wearing a delivery app, and it is the
     * kind of capability somebody else finds first.
     *
     * <p>So a withdrawal is capped at what the person has actually earned:
     *
     * <pre>
     * withdrawable = max(0, lifetime earned − lifetime paid out)
     * ceiling      = min(available, withdrawable)
     * </pre>
     *
     * <p>Both halves are read from the records of record — the ledger's entries
     * and the payout rows — rather than kept in a column on the worker. A stored
     * counter is one missed write away from disagreeing with the entries it
     * summarises, and the first thing anybody does with a disagreement is
     * believe the counter.
     *
     * <p>The alternatives, and why not:
     *
     * <ul>
     *   <li><b>A separate EARNINGS bucket</b> that work is paid into and payouts
     *       come out of. Structurally the honest answer, since it makes the cap
     *       a balance instead of a policy. It also needs a migration, a second
     *       number on every screen that shows a worker their money, and a
     *       transfer verb between two of a person's own pockets that every
     *       vertical paying a worker would have to learn. It is where this
     *       should go if withdrawal volume ever justifies it, and the arithmetic
     *       here would survive the move unchanged.</li>
     *   <li><b>Clamping silently</b> to the ceiling. Cheaper, and it lies:
     *       somebody asks for 50, sees 30 leave, and the app has nothing to tell
     *       them. The refusal names the number instead — a 409, not a 400,
     *       because the request is well formed and it is the state of their
     *       account that says no.</li>
     *   <li><b>No cap here, and a limit on the provider's side.</b> Stripe
     *       cannot know which half of a balance was earned, so it is not able to
     *       be the one that says.</li>
     * </ul>
     *
     * <p><b>What this deliberately does not catch.</b> Earnings are counted
     * gross, so a worker who earns 100, spends it, and later tops up 100 by card
     * can still withdraw 100: the cap bounds a lifetime of withdrawals by a
     * lifetime of work, not the specific coins. Closing that would mean netting
     * every spend of an earned kind against earnings, which charges a driver for
     * taking a ride home and still would not be exact, since money is fungible
     * and nothing in the ledger says which dollar left. The bound that matters
     * holds either way: <em>nobody can ever withdraw more than the platform has
     * paid them for work</em>, which is the sentence this cap exists to make
     * true.
     */
    private long withdrawable(UUID me, long lifetimeEarnedMinor) {
        return Math.max(0, lifetimeEarnedMinor - payouts.lifetimePaidOutMinor(OwnerKind.USER, me));
    }

    /**
     * Why the answer was no, said in terms of whichever half of the ceiling
     * actually bit.
     *
     * <p>Three quite different facts arrive at the same refusal, and telling
     * them apart is the difference between a message somebody can act on and one
     * that reads as a bug. "You have earned nothing yet" is a wait. "You earned
     * it and spent it" is an explanation of an empty wallet. And "most of this
     * balance is money you put in yourself" is a rule nobody has ever had
     * explained to them, which is the one that has to be spelled out rather than
     * implied by a number.
     */
    private static String refusal(long available, long withdrawable) {
        if (withdrawable <= 0) {
            return "There's nothing to withdraw yet — a withdrawal comes out of what "
                + "you've earned working.";
        }
        if (available <= 0) {
            return "Your wallet is empty — you've earned " + display(withdrawable)
                + ", but it has already been spent.";
        }
        return withdrawable < available
            ? "You can withdraw up to " + display(withdrawable) + " — a withdrawal is limited "
                + "to what you've earned working, and the rest of your balance stays in your "
                + "wallet."
            : "You can withdraw up to " + display(available) + ", which is your whole balance.";
    }

    /**
     * 404, not 403 — the same answer this module gives everywhere for work that
     * isn't yours: there is no worker here.
     *
     * <p>Deliberately unlike {@code GET /v1/dispatch/me}, which answers anybody
     * with empty lists because "am I a driver" is a question the app asks before
     * it knows. This is money, the app only opens it once the answer is yes, and
     * a wallet full of zeroes for somebody who has never been approved is a
     * screen that invites a support ticket.
     *
     * <p><b>Suspension does not block any of this.</b> A suspended worker is
     * offered nothing and can earn nothing more, but what they already earned is
     * theirs, and holding somebody's wages as leverage over a review is not a
     * thing this platform does.
     */
    private void requireRegistration(UUID me) {
        if (workers.findByUserIdOrderByKindAsc(me).isEmpty()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "You're not registered to drive or deliver");
        }
    }

    private static String display(long minor) {
        return "%d.%02d".formatted(minor / 100, Math.abs(minor % 100));
    }
}
