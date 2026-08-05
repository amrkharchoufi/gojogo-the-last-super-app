package com.gojogo.notifications.internal;

import com.gojogo.services.BookingConfirmed;
import com.gojogo.services.BookingReminder;
import com.gojogo.services.BookingRequested;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;

/**
 * The SPECS §12 booking pushes: requested (to the provider), confirmed (to the
 * customer), and the 24h/1h reminders. Push-only, like every queue-shaped
 * event — the booking list is the record, the push opens it.
 */
@Component
class BookingNotificationListener {

    private static final DateTimeFormatter WHEN =
        DateTimeFormatter.ofPattern("EEE d MMM, HH:mm");

    private final ApnsPushSender apns;

    BookingNotificationListener(ApnsPushSender apns) {
        this.apns = apns;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onRequested(BookingRequested event) {
        if (event.providerOwnerId() == null) return;
        apns.notifySystem(event.providerOwnerId(), "New booking request",
            event.serviceName() + " — " + when(event.startsAt())
                + ". Confirm it before it times out.",
            "provider-booking", event.bookingId());
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onConfirmed(BookingConfirmed event) {
        apns.notifySystem(event.customerId(), "Booking confirmed",
            event.serviceName() + " — " + when(event.startsAt()) + ".",
            "booking", event.bookingId());
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onReminder(BookingReminder event) {
        String lead = event.hoursAhead() >= 24 ? "tomorrow" : "in about an hour";
        apns.notifySystem(event.customerId(), "Upcoming booking",
            event.serviceName() + " is " + lead + " — " + when(event.startsAt()) + ".",
            "booking", event.bookingId());
    }

    /** Rendered in UTC — the push has no idea what zone the phone is in, and a
     *  wrong guess is worse than an honest one. */
    private static String when(OffsetDateTime at) {
        return WHEN.format(at.atZoneSameInstant(ZoneOffset.UTC)) + " UTC";
    }
}
