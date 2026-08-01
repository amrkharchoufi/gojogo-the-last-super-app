/**
 * Travel — ride-hailing ({@code travel} schema, ARCHITECTURE.md §10 Phase 3 M3,
 * SPECS.md §2).
 *
 * <p>A vertical, and the first thing in this system that ever asks
 * {@code dispatch} for anything. M1 built the matching and M2 built the drivers;
 * until this module existed neither had been given a job to fill.
 *
 * <p><strong>The one thing that makes a ride different from a delivery order is
 * negotiation.</strong> A delivery is priced by the server and paid; a ride has a
 * price two people agree on — the app suggests one, the rider may offer another,
 * and a driver may counter. That is why fares live here and offers are rows, and
 * why {@code dispatch} cannot own this half: dispatch's offer book asks "will you
 * do this job" and has no opinion about money. A driver who wants a different
 * fare therefore <em>declines</em> the dispatch offer and posts a counter here;
 * when the rider accepts one, this module calls {@code DispatchApi.assign} to
 * close the loop.
 *
 * <p><strong>The fare freezes at CONFIRMED and is never recomputed.</strong> A
 * price that moves after a handshake is not a handshake. The suggestion and the
 * rider's opening offer are both kept alongside the agreed figure, because "you
 * charged 40 when the app said 32" is a question somebody will eventually ask and
 * a receipt should be able to answer it.
 *
 * <p><strong>Money moves once, at completion, and the driver keeps all of
 * it.</strong> Rides carry no commission (SPECS §1) — the platform's revenue is
 * the ride-hailing tokens of Phase 3 M4 — so the settlement is one transfer from
 * the rider's wallet to the driver's, not a split. There is no escrow, per the
 * spec; what this module adds is a balance check at CONFIRMED, so a fare nobody
 * can pay is refused while the trip can still not happen rather than after
 * somebody has been driven across a city.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Travel")
package com.gojogo.travel;
