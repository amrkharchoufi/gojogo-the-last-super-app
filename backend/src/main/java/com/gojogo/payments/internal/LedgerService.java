package com.gojogo.payments.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.payments.AccountRef;
import com.gojogo.payments.Bucket;
import com.gojogo.payments.InsufficientFundsException;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.MoneyReceived;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.WalletApi;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.EnumMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

/**
 * The ledger. Every movement of money in GojoGo goes through
 * {@link #post}, and nothing else writes to {@code payments.account}.
 *
 * <p>Three rules hold everything else up:
 *
 * <ol>
 *   <li><b>Two sides, always.</b> A movement debits one account and credits
 *       another, so the sum of all balances never changes and money cannot be
 *       created by a bug — only misplaced, which is findable.</li>
 *   <li><b>The idempotency key is unique in the database.</b> A retried
 *       checkout, a replayed webhook and a double-tapped button collapse onto
 *       one entry, and the second caller is told so rather than lied to.</li>
 *   <li><b>Accounts are locked in a fixed order.</b> A capture touches four or
 *       five rows; locking them in a deterministic order is the difference
 *       between a busy Friday and a deadlock storm.</li>
 * </ol>
 */
@Service
class LedgerService implements WalletApi {

    private static final Logger log = LoggerFactory.getLogger(LedgerService.class);

    private static final String CURRENCY_KEY = "platform.currency";
    private static final String DEFAULT_CURRENCY = "USD";

    /**
     * Credits worth telling a person about. A hold and a release move money
     * between someone's own pockets — announcing those would train people to
     * ignore the notifications that matter.
     */
    private static final Set<LedgerKind> ANNOUNCED = Set.of(
        LedgerKind.TOPUP, LedgerKind.REFUND, LedgerKind.REWARD, LedgerKind.TIP,
        LedgerKind.CAPTURE, LedgerKind.TRANSFER, LedgerKind.STAKE_RELEASE);

    private final AccountRepository accounts;
    private final LedgerEntryRepository entries;
    private final ConfigApi config;
    private final ApplicationEventPublisher events;

    LedgerService(AccountRepository accounts, LedgerEntryRepository entries,
                  ConfigApi config, ApplicationEventPublisher events) {
        this.accounts = accounts;
        this.entries = entries;
        this.config = config;
        this.events = events;
    }

    @Override
    public String currency() {
        return config.string(CURRENCY_KEY, DEFAULT_CURRENCY).toUpperCase();
    }

    @Override
    @Transactional(readOnly = true)
    public Balances balancesOf(OwnerKind ownerKind, UUID ownerId) {
        String currency = currency();
        Map<Bucket, Long> byBucket = new EnumMap<>(Bucket.class);
        for (Account account : accounts.findByOwnerKindAndOwnerIdAndCurrency(
                ownerKind, ownerId, currency)) {
            byBucket.put(account.getBucket(), account.getBalanceMinor());
        }
        return new Balances(currency,
            byBucket.getOrDefault(Bucket.AVAILABLE, 0L),
            byBucket.getOrDefault(Bucket.ESCROW, 0L),
            byBucket.getOrDefault(Bucket.STAKING, 0L),
            byBucket.getOrDefault(Bucket.TOKENS, 0L),
            byBucket.getOrDefault(Bucket.REWARDS, 0L));
    }

    @Override
    @Transactional
    public Movement hold(OwnerKind ownerKind, UUID ownerId, long amountMinor,
                         Reference ref, String idempotencyKey) {
        return post(AccountRef.of(ownerKind, ownerId, Bucket.AVAILABLE),
            AccountRef.of(ownerKind, ownerId, Bucket.ESCROW),
            amountMinor, LedgerKind.HOLD, ref, idempotencyKey);
    }

    @Override
    @Transactional
    public Movement release(OwnerKind ownerKind, UUID ownerId, long amountMinor,
                            Reference ref, String idempotencyKey) {
        return post(AccountRef.of(ownerKind, ownerId, Bucket.ESCROW),
            AccountRef.of(ownerKind, ownerId, Bucket.AVAILABLE),
            amountMinor, LedgerKind.RELEASE, ref, idempotencyKey);
    }

    /**
     * Settles a hold in one transaction: all of the splits or none of them.
     *
     * <p>Each split gets its own entry — so a receipt can say "food to the
     * restaurant, commission to GojoGo, tip to the courier" — and its own
     * idempotency key derived from the settlement's, so a retry after a partial
     * failure resumes rather than double-paying whatever already landed.
     */
    @Override
    @Transactional
    public List<Movement> capture(OwnerKind payerKind, UUID payerId, List<Split> splits,
                                  Reference ref, String idempotencyKey) {
        if (splits == null || splits.isEmpty()) {
            throw new IllegalArgumentException("A capture needs at least one payee");
        }
        AccountRef escrow = AccountRef.of(payerKind, payerId, Bucket.ESCROW);
        List<Movement> movements = new ArrayList<>(splits.size());
        for (int i = 0; i < splits.size(); i++) {
            Split split = splits.get(i);
            if (split.amountMinor() <= 0) continue; // a zero fee is not an entry
            movements.add(post(escrow, split.payee(), split.amountMinor(), split.kind(),
                Reference.of(ref.kind(), ref.id(),
                    split.memo() == null || split.memo().isBlank() ? ref.memo() : split.memo()),
                idempotencyKey + ":" + i + ":" + split.kind()));
        }
        return movements;
    }

    @Override
    @Transactional
    public Movement transfer(AccountRef from, AccountRef to, long amountMinor, LedgerKind kind,
                             Reference ref, String idempotencyKey) {
        return post(from, to, amountMinor, kind, ref, idempotencyKey);
    }

    @Override
    @Transactional
    public Movement refund(AccountRef from, AccountRef to, long amountMinor,
                           Reference ref, String idempotencyKey) {
        return post(from, to, amountMinor, LedgerKind.REFUND, ref, idempotencyKey);
    }

    @Override
    @Transactional(readOnly = true)
    public List<Entry> statement(OwnerKind ownerKind, UUID ownerId, int limit) {
        String currency = currency();
        List<Account> owned = accounts.findByOwnerKindAndOwnerIdAndCurrency(
            ownerKind, ownerId, currency);
        if (owned.isEmpty()) return List.of();

        Map<UUID, Account> byId = new LinkedHashMap<>();
        owned.forEach(account -> byId.put(account.getId(), account));
        List<LedgerEntry> rows = entries.statement(List.copyOf(byId.keySet()),
            PageRequest.of(0, Math.clamp(limit, 1, 200)));

        List<Entry> statement = new ArrayList<>(rows.size());
        for (LedgerEntry row : rows) {
            // Signed from this owner's point of view. An entry between two of
            // their own buckets (a hold) nets to zero and is dropped: it is not
            // a transaction, it is bookkeeping.
            boolean credited = byId.containsKey(row.getCreditAccountId());
            boolean debited = byId.containsKey(row.getDebitAccountId());
            if (credited && debited) continue;
            statement.add(new Entry(row.getId(),
                credited ? row.getAmountMinor() : -row.getAmountMinor(),
                row.getCurrency(), row.getKind(), row.getRefKind(), row.getRefId(),
                row.getMemo(), row.getCreatedAt()));
        }
        return statement;
    }

    @Override
    @Transactional(readOnly = true)
    public List<Entry> entriesFor(String refKind, UUID refId) {
        return entries.findByRefKindAndRefIdOrderByCreatedAtAsc(refKind, refId).stream()
            .map(row -> new Entry(row.getId(), row.getAmountMinor(), row.getCurrency(),
                row.getKind(), row.getRefKind(), row.getRefId(), row.getMemo(),
                row.getCreatedAt()))
            .toList();
    }

    // MARK: The one write

    /**
     * Moves {@code amountMinor} from one account to another, or reports that
     * this exact operation already happened.
     *
     * <p>Package-private rather than public on the API: everything the rest of
     * the platform needs is a named verb above, and a general "move money from
     * anywhere to anywhere" is not a capability to hand out.
     */
    @Transactional
    Movement post(AccountRef from, AccountRef to, long amountMinor, LedgerKind kind,
                  Reference ref, String idempotencyKey) {
        if (amountMinor <= 0) {
            throw new IllegalArgumentException("A movement must be for a positive amount");
        }
        if (idempotencyKey == null || idempotencyKey.isBlank()) {
            throw new IllegalArgumentException("Every movement needs an idempotency key");
        }
        if (from.equals(to)) {
            throw new IllegalArgumentException("A movement needs two different accounts");
        }

        // The cheap path, and the common one on a retry: the operation already
        // happened, so report it and touch nothing. (A concurrent duplicate
        // still loses on the unique index below — this check is the fast lane,
        // not the guarantee.)
        Optional<LedgerEntry> existing = entries.findByIdempotencyKey(idempotencyKey);
        if (existing.isPresent()) {
            return new Movement(existing.get().getId(), existing.get().getAmountMinor(), true);
        }

        String currency = currency();
        Map<AccountRef, Account> locked = lockAll(List.of(from, to), currency);
        Account source = locked.get(from);
        Account destination = locked.get(to);

        if (!source.canCover(amountMinor)) {
            throw new InsufficientFundsException(amountMinor, source.getBalanceMinor(), currency);
        }

        source.add(-amountMinor);
        destination.add(amountMinor);
        LedgerEntry entry = entries.save(new LedgerEntry(idempotencyKey, source.getId(),
            destination.getId(), amountMinor, currency, kind,
            ref == null ? "" : ref.kind(), ref == null ? null : ref.id(),
            ref == null ? "" : ref.memo()));

        announce(destination, amountMinor, currency, kind, ref);
        return new Movement(entry.getId(), amountMinor, false);
    }

    /**
     * Takes the row locks for a movement, always in the same global order.
     *
     * <p>Order is what prevents deadlock: two settlements that touch the same
     * merchant and the same platform account will queue behind each other
     * instead of each holding what the other wants.
     */
    private Map<AccountRef, Account> lockAll(List<AccountRef> refs, String currency) {
        List<AccountRef> ordered = refs.stream()
            .distinct()
            .sorted(Comparator.comparing(LedgerService::lockOrder))
            .toList();
        for (AccountRef ref : ordered) {
            accounts.ensure(ref.ownerKind().name(), ref.ownerId(), ref.bucket().name(),
                currency, ref.ownerKind() == OwnerKind.EXTERNAL);
        }
        Map<AccountRef, Account> locked = new LinkedHashMap<>();
        for (AccountRef ref : ordered) {
            locked.put(ref, accounts.lock(ref.ownerKind(), ref.ownerId(), ref.bucket(), currency)
                .orElseThrow(() -> new IllegalStateException(
                    "Account vanished between creation and lock: " + ref)));
        }
        return locked;
    }

    private static String lockOrder(AccountRef ref) {
        return ref.ownerKind().name() + '|' + ref.ownerId() + '|' + ref.bucket().name();
    }

    /**
     * Tells a person their spendable balance went up. Users only: a merchant's
     * earnings are announced by the vertical that owns the merchant, since only
     * it knows which human to tell.
     */
    private void announce(Account destination, long amountMinor, String currency,
                          LedgerKind kind, Reference ref) {
        if (destination.getOwnerKind() != OwnerKind.USER
            || destination.getBucket() != Bucket.AVAILABLE
            || !ANNOUNCED.contains(kind)) {
            return;
        }
        events.publishEvent(new MoneyReceived(destination.getOwnerId(), amountMinor, currency,
            kind, ref == null ? "" : ref.kind(), ref == null ? null : ref.id(),
            ref == null ? "" : ref.memo(), java.time.OffsetDateTime.now()));
    }

    // MARK: Fees — read by the verticals through PricingService, not directly

    void logStartup(boolean stripeConfigured) {
        log.info("GoJo Wallet on: currency {}, Stripe {}", currency(),
            stripeConfigured ? "configured" : "OFF (internal movements only — no card, no payout)");
    }
}
