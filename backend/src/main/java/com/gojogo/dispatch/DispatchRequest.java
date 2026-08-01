package com.gojogo.dispatch;

import java.time.OffsetDateTime;
import java.util.Set;
import java.util.UUID;

/**
 * One vertical asking for one worker.
 *
 * <p>Everything here is what dispatch needs to <em>find somebody</em>. There is
 * no fare, no basket and no money, and that omission is the module boundary: a
 * request that carried a price would make dispatch a party to the transaction,
 * and then two modules would own what a trip is worth.
 *
 * @param jobKind     what the work is, as a label dispatch never interprets
 * @param jobRefId    the vertical's own id for it. Unique per kind — asking
 *                    twice for the same thing finds the search already running
 *                    rather than opening a second one
 * @param workerKind  which registry to search
 * @param categories  every vehicle category that would do. A rider wanting an XL
 *                    passes one; a small basket passes bike, scooter and car
 * @param requestedBy the customer, carried so a worker's offer card can name
 *                    them without dispatch reading into another module. Optional
 * @param startAfter  when the search may begin, or null for now. This is the
 *                    whole of SPECS §3's "approaching readiness" trigger — a
 *                    courier search that must not start until the kitchen is
 *                    nearly done is a job whose first wave is in the future, and
 *                    a scheduled ride is the same thing with a longer wait
 */
public record DispatchRequest(JobKind jobKind, UUID jobRefId, WorkerKind workerKind,
                              Set<VehicleCategory> categories, UUID requestedBy,
                              double pickupLatitude, double pickupLongitude, String pickupLabel,
                              Double dropoffLatitude, Double dropoffLongitude, String dropoffLabel,
                              String note, OffsetDateTime startAfter) {
}
