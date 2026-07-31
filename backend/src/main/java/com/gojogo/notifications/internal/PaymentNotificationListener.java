package com.gojogo.notifications.internal;

import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.MoneyReceived;
import com.gojogo.payments.PayoutSent;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * Money pushes (SPECS.md §12: "payment received / payout sent").
 *
 * <p>{@code AFTER_COMMIT}, without exception: telling someone their wallet has
 * been topped up before the credit is durable is the one notification in this
 * product that would be actively harmful to send early.
 *
 * <p>The wording deliberately never includes a balance. A push is visible on a
 * lock screen, so it says what happened, not what someone is worth.
 */
@Component
class PaymentNotificationListener {

    private final ApnsPushSender apns;

    PaymentNotificationListener(ApnsPushSender apns) {
        this.apns = apns;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onMoneyReceived(MoneyReceived event) {
        String amount = display(event.amountMinor(), event.currency());
        String title;
        String body;
        if (event.kind() == LedgerKind.TOPUP) {
            title = "Wallet topped up";
            body = amount + " is ready to spend.";
        } else if (event.kind() == LedgerKind.REFUND) {
            title = "Refunded";
            body = amount + " is back in your wallet.";
        } else {
            title = "You received " + amount;
            body = event.memo() == null || event.memo().isBlank()
                ? "It's in your GoJo Wallet." : event.memo();
        }
        apns.notifySystem(event.profileId(), title, body, "wallet", event.refId());
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onPayoutSent(PayoutSent event) {
        if (event.profileId() == null) return; // a payout nobody personally asked for
        apns.notifySystem(event.profileId(), "Payout on its way",
            display(event.amountMinor(), event.currency())
                + " is heading to your bank. Stripe pays it out on its own schedule.",
            "payout", event.payoutId());
    }

    /** Minor units are the only representation this platform stores; the one
     *  place they become a decimal is where a human reads them. */
    private static String display(long minor, String currency) {
        return "%s %d.%02d".formatted(currency, minor / 100, Math.abs(minor % 100));
    }
}
