package com.gojogo.notifications.internal;

import com.gojogo.payments.TokensRanOut;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * "You're nearly out of tokens" — SPECS §4's low-balance push, and §12's entry
 * for it.
 *
 * <p>Push only, no activity row, like every other working-driver notification in
 * this module: a feed entry saying a balance was once low is a record of nothing,
 * and the thing that needs to happen is a top-up now.
 *
 * <p>The two cases are worded apart because they are different facts. Above zero
 * is a warning — work is still arriving. At zero the driver has already stopped
 * being offered trips, silently, and nothing else in the system will ever tell
 * them: dispatch simply skips them, which is exactly right and completely
 * invisible.
 */
@Component
class TokenNotificationListener {

    private final ApnsPushSender apns;

    TokenNotificationListener(ApnsPushSender apns) {
        this.apns = apns;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onTokensRanOut(TokensRanOut event) {
        String title;
        String body;
        if (event.isEmpty()) {
            title = "You're out of ride tokens";
            body = "New trips won't be offered to you until you top up.";
        } else {
            title = "Ride tokens running low";
            body = event.remainingTokens() == 1
                ? "One token left. Top up before it runs out."
                : event.remainingTokens() + " tokens left. Top up before they run out.";
        }
        apns.notifySystem(event.profileId(), title, body, "tokens", null);
    }
}
