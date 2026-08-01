package com.gojogo.notifications.internal;

import com.gojogo.travel.RideStatusChanged;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * Ride pushes — SPECS §12's "ride offer / confirmed / arriving / completed".
 *
 * <p>Push only, no activity row, for the same reason orders and partner reviews
 * get none: the feed is built around an actor whose profile decorates the row,
 * and the *ride* is its own record. The push opens it.
 *
 * <p>Not every transition is worth a phone lighting up, and the filter here is
 * sharper than the order one because the person waiting is standing outside.
 * CONFIRMED and ARRIVING are the two that matter — somebody took your trip, and
 * they are outside — plus the ending, whichever ending it was. IN_TRIP is
 * announced by a car door.
 */
@Component
class RideNotificationListener {

    private final ApnsPushSender apns;

    RideNotificationListener(ApnsPushSender apns) {
        this.apns = apns;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onStatusChanged(RideStatusChanged event) {
        String other = event.otherPartyName() == null || event.otherPartyName().isBlank()
            ? "Your driver" : event.otherPartyName();
        String title;
        String body;
        switch (event.status()) {
            case "CONFIRMED" -> {
                title = other + " is coming to get you";
                body = fare(event, "Tap to see where they are.");
            }
            case "ARRIVING" -> {
                title = other + " is on the way";
                body = "Tap to follow them in.";
            }
            case "COMPLETED" -> {
                title = "Trip complete";
                body = fare(event, "Rate your driver in the app.");
            }
            case "CANCELLED_RIDER", "CANCELLED_DRIVER" -> {
                title = "Your ride was cancelled";
                // Deliberately does not say who cancelled: this is only ever
                // sent to the *other* party, so they already know it wasn't them.
                body = "Nothing was charged unless a driver was already on the way.";
            }
            case "EXPIRED" -> {
                title = "No drivers took your trip";
                body = "Nobody nearby was free. Try again, or offer a little more.";
            }
            default -> {
                return;
            }
        }
        apns.notifySystem(event.recipientId(), title, body, "ride", event.rideId());
    }

    private static String fare(RideStatusChanged event, String fallback) {
        if (event.fareMinor() <= 0) return fallback;
        return String.format("%s %.2f — %s", event.currency(),
            event.fareMinor() / 100d, fallback);
    }
}
