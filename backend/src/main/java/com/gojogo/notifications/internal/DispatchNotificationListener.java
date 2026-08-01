package com.gojogo.notifications.internal;

import com.gojogo.dispatch.DispatchOffered;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * The push that makes an offer worth sending.
 *
 * <p>An offer lives for thirty seconds. A driver whose phone is in their pocket
 * will miss every single one of them unless something makes it ring, which is
 * why this is the one listener in {@code notifications} whose absence would break
 * a product loop rather than just make it quieter.
 *
 * <p><b>Push only, no activity row</b> — the same call {@code OrderNotification}
 * makes, for a stronger reason: by the time anybody scrolled back to an activity
 * feed the work would have been given to somebody else, and a permanent record
 * of jobs you didn't get is a feed nobody wants.
 *
 * <p>Nothing is sent when a job is <em>assigned</em>. The worker who accepted was
 * looking at the screen when they did, and the customer learns from the vertical
 * that asked — {@code travel} or {@code delivery} — which is the module that
 * knows what to call the thing.
 */
@Component
class DispatchNotificationListener {

    private final ApnsPushSender apns;

    DispatchNotificationListener(ApnsPushSender apns) {
        this.apns = apns;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onOffered(DispatchOffered event) {
        String title = switch (event.jobKind()) {
            case RIDE -> "New ride request";
            case DELIVERY -> "New delivery";
        };
        String where = event.pickupLabel() == null || event.pickupLabel().isBlank()
            ? "Tap to see it before it goes."
            : "Pickup at " + event.pickupLabel() + ". Tap to see it before it goes.";
        apns.notifySystem(event.workerUserId(), title, where, "dispatch", event.jobId());
    }
}
