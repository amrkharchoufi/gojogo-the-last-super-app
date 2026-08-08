package com.gojogo.services.internal;

import com.gojogo.services.BookingDirectoryApi;
import org.springframework.stereotype.Component;

import java.time.OffsetDateTime;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

/**
 * {@link BookingDirectoryApi} over {@link BookingService} — the customer's own
 * booking list, filtered to what is still ahead of them.
 */
@Component
class BookingDirectoryApiAdapter implements BookingDirectoryApi {

    private final BookingService bookings;

    BookingDirectoryApiAdapter(BookingService bookings) {
        this.bookings = bookings;
    }

    @Override
    public List<Booking> upcomingFor(UUID customerId, int limit) {
        int size = Math.clamp(limit, 1, 50);
        OffsetDateTime now = OffsetDateTime.now();
        // mine() is newest-requested-first, which is the order a history screen
        // wants and the opposite of what "coming up" means; take a generous
        // page, keep what is still ahead, and re-sort by when it happens.
        return bookings.mine(customerId, Math.min(size * 4, 100)).stream()
            .filter(b -> b.startsAt() != null && b.startsAt().isAfter(now))
            .filter(b -> BookingStatus.valueOf(b.status()).occupiesSlot())
            .sorted(Comparator.comparing(ServiceDtos.BookingResponse::startsAt))
            .limit(size)
            .map(b -> new Booking(b.id(), b.serviceName(), b.providerName(), b.status(),
                b.startsAt(), b.durationMinutes(), b.priceCents(), b.currency()))
            .toList();
    }
}
