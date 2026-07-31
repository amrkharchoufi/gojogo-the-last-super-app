package com.gojogo.payments.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * Proves the shortcut. Balances are materialised on the account row so a
 * checkout doesn't have to sum an append-only table that grows forever — this
 * re-derives every balance from the entries and shouts if one has drifted
 * (SPECS.md §1: "verified by a nightly job").
 *
 * <p>It corrects nothing. A drift means either a bug or a hand-written UPDATE,
 * and in both cases the right response is a person looking at it — an automatic
 * "fix" would erase the evidence of how it happened. What the job guarantees is
 * that nobody finds out a month later.
 *
 * <p>It also sweeps abandoned checkout sessions, since it is already the thing
 * that runs when nobody is watching.
 */
@Component
class LedgerAuditJob {

    private static final Logger log = LoggerFactory.getLogger(LedgerAuditJob.class);

    private final AccountRepository accounts;
    private final LedgerEntryRepository entries;
    private final PaymentsService payments;

    LedgerAuditJob(AccountRepository accounts, LedgerEntryRepository entries,
                   PaymentsService payments) {
        this.accounts = accounts;
        this.entries = entries;
        this.payments = payments;
    }

    /** 03:17 rather than 03:00 — nothing else in this system runs at 17 past. */
    @Scheduled(cron = "0 17 3 * * *")
    @Transactional(readOnly = true)
    public void audit() {
        List<Account> all = accounts.findAll();
        long drifted = 0;
        long total = 0;
        for (Account account : all) {
            long derived = entries.derivedBalance(account.getId());
            total += account.getBalanceMinor();
            if (derived != account.getBalanceMinor()) {
                drifted++;
                log.error("LEDGER DRIFT on account {} ({} {} {}): balance says {}, entries say {}",
                    account.getId(), account.getOwnerKind(), account.getOwnerId(),
                    account.getBucket(), account.getBalanceMinor(), derived);
            }
        }
        if (drifted == 0) {
            // The sum of every balance must be zero: money is only ever moved
            // between accounts, and the EXTERNAL account is the negative mirror
            // of everything that has come in.
            log.info("Ledger audit: {} accounts, all balanced, net {} (expected 0)",
                all.size(), total);
        } else {
            log.error("Ledger audit: {} of {} accounts have drifted — needs a human",
                drifted, all.size());
        }
    }

    /** Checkout sessions nobody ever paid, so a wallet screen stops showing a
     *  "pending" top-up from last month. */
    @Scheduled(cron = "0 47 * * * *")
    public void sweepAbandonedTopUps() {
        int swept = payments.sweepAbandoned();
        if (swept > 0) {
            log.info("Closed {} abandoned checkout session(s)", swept);
        }
    }
}
