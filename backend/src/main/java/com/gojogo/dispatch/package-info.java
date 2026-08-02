/**
 * Dispatch — who is out there, where they are, and who was offered the work
 * ({@code dispatch} schema, ARCHITECTURE.md §10 Phase 3 M1, SPECS.md §3).
 *
 * <p>A platform module, and the narrowest one in the system on purpose. It
 * answers exactly one question — <em>which available person should be asked to
 * do this, and did they say yes</em> — and it deliberately does not know what
 * "this" is. A ride's fare, a basket's contents, an order's state machine and
 * every cent of money belong to the vertical that asked. What crosses the
 * boundary is a kind, an opaque id, a place and a category.
 *
 * <p>That narrowness is what lets one module serve two verticals that otherwise
 * have nothing in common. A rider looking for a car and a restaurant looking for
 * a courier are the same search with different filters, and building it twice
 * would guarantee two answers to "is this driver busy".
 *
 * <p><strong>The registry is created by approval, never by a person.</strong>
 * {@link com.gojogo.dispatch.DriverProvisioningApi} and
 * {@link com.gojogo.dispatch.CourierProvisioningApi} are the only ways a worker
 * row comes into existence, called by {@code partner} when a human approves an
 * application — the same one-way {@code partner → vertical} shape
 * {@code delivery.MerchantProvisioningApi} has had since 2b M6, and the landing
 * place a {@code DRIVER} approval has been refusing toward ever since. There is
 * no endpoint that makes you a driver.
 *
 * <p><strong>Offers go out, results come back as events.</strong> Dispatch
 * publishes {@link com.gojogo.dispatch.DispatchAssigned} and
 * {@link com.gojogo.dispatch.DispatchExhausted}; the vertical listens. It does
 * not call back into {@code travel} or {@code delivery}, because a platform
 * module that knows the name of a vertical is a platform module that will
 * eventually be edited every time one is added.
 *
 * <p><strong>Money is the one exception to "dispatch knows nothing about the
 * job", and it is not an exception to the narrowness.</strong> Phase 4 M2 adds
 * {@code /v1/dispatch/me/wallet} and {@code /payouts}, and with them a
 * dependency on {@code payments} ({@code WalletApi}, {@code PayoutApi},
 * {@code OwnerKind}, {@code LedgerKind}) — platform to platform, and no cycle,
 * because payments does not know this module exists. The surface is here rather
 * than in payments for the reason {@code PayoutApi}'s javadoc already gave: it
 * is "called by whichever module owns the payee", and the worker registry is the
 * only thing that can prove a caller is somebody the platform pays for work.
 * Payments knows what is owed and must not learn who may ask for it, which is
 * the same reasoning that put a restaurant's wallet on {@code delivery}'s
 * {@code /mine} surface in 2e M3. Note what still does <em>not</em> cross: no
 * fare, no basket, no order — dispatch reads a balance and a lifetime total for
 * a person, and neither of those says what the work was.
 *
 * <p><strong>Presence is Postgres, not Redis</strong> (SPECS §3 says Redis GEO,
 * and at real scale it should be). The read is "available workers of this kind
 * within N km", the table is small and heavily filtered, and an ElastiCache
 * cluster bills by the hour whether or not anybody is driving. The bounding box
 * is computed in {@link com.gojogo.dispatch} internals and the ranking is done in
 * Java over the shortlist, so swapping the store later changes one repository
 * method and no caller.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Dispatch")
package com.gojogo.dispatch;
