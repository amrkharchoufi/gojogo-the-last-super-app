package com.gojogo.services;

import java.util.List;
import java.util.UUID;

/**
 * The read side of the services vertical, for other modules.
 *
 * <p>{@link ProviderProvisioningApi} is how a provider comes into existence;
 * this is how somebody asks what a customer has coming up. Added for
 * Madeleine's {@code get_my_bookings} tool (MADELEINE.md §5).
 *
 * <p>Customer-side only, deliberately. A provider's queue is a work surface
 * with its own authorisation, and it stays on {@code /v1/services/provider}
 * where the ownership check lives.
 */
public interface BookingDirectoryApi {

    /**
     * This customer's appointments that have not happened yet, soonest first.
     *
     * <p>Cancelled and declined bookings are left out: "what have I got coming
     * up" is a question about the future, and a list that answers it with
     * things that will not happen is worse than a short list.
     *
     * @param limit clamped to 1..50
     */
    List<Booking> upcomingFor(UUID customerId, int limit);

    /**
     * @param priceMinor null while a PRICE_ON_QUOTE booking is still waiting
     *                   for its number — not free, not zero, not yet known
     */
    record Booking(UUID id, String serviceName, String providerName, String status,
                   java.time.OffsetDateTime startsAt, int durationMinutes,
                   Long priceMinor, String currency) {
    }
}
