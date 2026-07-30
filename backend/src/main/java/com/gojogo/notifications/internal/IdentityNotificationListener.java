package com.gojogo.notifications.internal;

import com.gojogo.kyc.IdentityVerified;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * Tells someone their ID check passed.
 *
 * <p>Worth a push precisely because of when it arrives: an identity check
 * finishes minutes or hours after the person put their phone down, often while
 * the app is closed, and the thing they were trying to do — submit a partner
 * application — is blocked until it does. Silence there reads as failure.
 *
 * <p>Push only, no activity row, for the same reason as a partner decision:
 * there is no actor whose profile would decorate the row. Only the pass is
 * notified — a refusal is delivered where the applicant can act on it, in the
 * flow itself, with the vendor's own wording rather than a notification's
 * paraphrase (SPECS §12's coverage matrix).
 *
 * <p>The event fires once per real transition, never per webhook delivery
 * (see {@code KycService}), so this cannot double-push on a vendor retry.
 */
@Component
class IdentityNotificationListener {

    private final ApnsPushSender apns;

    IdentityNotificationListener(ApnsPushSender apns) {
        this.apns = apns;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onVerified(IdentityVerified event) {
        apns.notifySystem(event.userId(), "You're verified",
            "Your identity check passed — you can finish your application now.",
            "identity", null);
    }
}
