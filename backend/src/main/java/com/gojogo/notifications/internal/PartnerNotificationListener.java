package com.gojogo.notifications.internal;

import com.gojogo.partner.PartnerReviewed;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * Tells an applicant what a reviewer decided.
 *
 * <p>Push only, no activity row: the activity feed is built around an actor
 * whose profile decorates the row, and there is no actor here — the platform
 * decided. The verdict itself lives on the application, which the push opens.
 *
 * <p>A rejection is the one notification in this product that carries a reason,
 * so the reviewer's note is the body. It's written for the applicant to read
 * (see {@code PartnerAdminController}), which is what makes that safe.
 *
 * <p>Unlike {@code MessageNotificationListener} this waits for the commit —
 * partner writes are JPA, so an approval that rolls back must not have already
 * told someone they're live.
 */
@Component
class PartnerNotificationListener {

    private final ApnsPushSender apns;

    PartnerNotificationListener(ApnsPushSender apns) {
        this.apns = apns;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onReviewed(PartnerReviewed event) {
        String business = event.businessName() == null || event.businessName().isBlank()
            ? "Your application" : event.businessName();
        String title;
        String body;
        switch (event.status()) {
            case "APPROVED" -> {
                title = business + " is approved";
                body = "Add your menu and open when you're ready.";
            }
            case "REJECTED" -> {
                title = "About your GojoGo application";
                body = note(event, "We couldn't approve it yet — open the app for details.");
            }
            case "SUSPENDED" -> {
                title = business + " has been suspended";
                body = note(event, "Your restaurant is hidden for now.");
            }
            // Nothing else is a decision worth waking a phone for.
            default -> {
                return;
            }
        }
        apns.notifySystem(event.userId(), title, body, "partner", event.accountId());
    }

    private static String note(PartnerReviewed event, String fallback) {
        return event.note() == null || event.note().isBlank() ? fallback : event.note();
    }
}
