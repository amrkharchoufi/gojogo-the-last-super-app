package com.gojogo.services.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.services.BookingReminder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.data.domain.PageRequest;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;

/**
 * The three clocks of the booking machine, in one poller class:
 *
 * <ul>
 * <li><b>Confirm timeout</b> — a provider who never answers inside CONFIG
 * {@code services.booking.confirm.hours} (24) is an auto-decline with an
 * auto-release (SPECS §7). A question nobody answered must not hold somebody's
 * money.</li>
 * <li><b>Capture window</b> — completed work settles after CONFIG
 * {@code services.booking.capture.hours} (48) with no complaint. Until the
 * dispute shape reaches this vertical, the window is support's time to
 * intervene by hand.</li>
 * <li><b>Reminders</b> — the SPECS §12 pushes at ~24h and ~1h before a
 * confirmed appointment, flagged on the row so each fires once.</li>
 * </ul>
 */
@Component
class BookingClockJobs {

    private static final Logger log = LoggerFactory.getLogger(BookingClockJobs.class);
    private static final int BATCH = 100;

    private final BookingRepository bookings;
    private final BookingService bookingService;
    private final ServiceOfferingRepository offerings;
    private final ConfigApi config;
    private final ApplicationEventPublisher events;

    BookingClockJobs(BookingRepository bookings, BookingService bookingService,
                     ServiceOfferingRepository offerings, ConfigApi config,
                     ApplicationEventPublisher events) {
        this.bookings = bookings;
        this.bookingService = bookingService;
        this.offerings = offerings;
        this.config = config;
        this.events = events;
    }

    @Scheduled(fixedDelayString = "${gojogo.services.timeout-poll-ms:300000}")
    void timeouts() {
        long hours = Math.max(1, config.number("services.booking.confirm.hours", 24));
        OffsetDateTime cutoff = OffsetDateTime.now().minusHours(hours);
        for (Booking booking : bookings.findByStatusAndRequestedAtBefore(
                BookingStatus.REQUESTED, cutoff, PageRequest.of(0, BATCH))) {
            try {
                bookingService.timeOut(booking.getId());
            } catch (OptimisticLockingFailureException anotherInstanceGotThere) {
                // the winner's decline stands
            } catch (Exception e) {
                log.error("Timing out booking {} failed", booking.getId(), e);
            }
        }
    }

    @Scheduled(fixedDelayString = "${gojogo.services.settle-poll-ms:600000}")
    void settlements() {
        long hours = Math.max(0, config.number("services.booking.capture.hours", 48));
        OffsetDateTime cutoff = OffsetDateTime.now().minusHours(hours);
        for (Booking booking : bookings.settleable(cutoff, PageRequest.of(0, BATCH))) {
            try {
                bookingService.settleCompleted(booking.getId());
            } catch (OptimisticLockingFailureException anotherInstanceGotThere) {
                // the winner's settlement stands
            } catch (Exception e) {
                log.error("Settling booking {} failed", booking.getId(), e);
            }
        }
    }

    @Scheduled(fixedDelayString = "${gojogo.services.reminder-poll-ms:300000}")
    void reminders() {
        remind(24);
        remind(1);
    }

    /** Fires for appointments inside the next {@code hoursAhead} hours that
     *  haven't had this reminder. The event goes out after the flag commits,
     *  so a crashed poller re-sends rather than double-sends. */
    @Transactional
    void remind(int hoursAhead) {
        OffsetDateTime now = OffsetDateTime.now();
        List<Booking> due = bookings.remindable(now, now.plusHours(hoursAhead), hoursAhead,
            PageRequest.of(0, BATCH));
        for (Booking booking : due) {
            booking.reminded(hoursAhead);
            bookings.save(booking);
            String serviceName = offerings.findById(booking.getServiceId())
                .map(ServiceOffering::getName)
                .orElse("Your booking");
            events.publishEvent(new BookingReminder(booking.getId(), booking.getCustomerId(),
                serviceName, booking.getStartsAt(), hoursAhead));
        }
    }
}
