/**
 * Payments and the GoJo Wallet — the platform's money
 * ({@code payments} schema, ARCHITECTURE.md §2b decision 2, SPECS.md §1).
 *
 * <p>Every movement of value in GojoGo is a pair of entries in one double-entry
 * ledger: a delivery order held and settled, a driver's stake locked, a
 * ride-hailing token spent, a verification reward paid, a tip, a refund, a
 * payout. There are no per-vertical balances — a vertical keeping its own would
 * eventually disagree with this one, and reconciling two ledgers is a job nobody
 * volunteers for.
 *
 * <p><strong>Stripe is the boundary, not the book.</strong> External money in (a
 * card top-up) and out (a Connect payout) are the only places a vendor is
 * needed, and both are mirrored as ledger entries against an EXTERNAL account.
 * No vertical ever talks to Stripe: they call
 * {@link com.gojogo.payments.WalletApi} with amounts in minor units, and what
 * happens to be behind it is this module's problem.
 *
 * <p><strong>Idempotency is the contract, not a nicety.</strong> Every write
 * takes a caller-chosen key that is UNIQUE in the database, so a retried
 * checkout, a replayed webhook and a double-tapped button all produce one
 * movement and report the same result. A caller that cannot name its operation
 * stably cannot use this API — which is the intended pressure.
 *
 * <p>What is deliberately <em>not</em> here: prices, fares, baskets, and what
 * anything is worth. Those belong to the vertical that sells the thing. This
 * module knows amounts, buckets and who is owed — never what was bought.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Payments")
package com.gojogo.payments;
