package com.gojogo.notifications.internal;

import com.gojogo.delivery.OrderStatusChanged;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * Order pushes — the consumer {@code OrderStatusChanged} has been publishing
 * into the void since 2b M4 (SPECS.md §12's push matrix, "lands with checkout").
 *
 * <p>Push only, no activity row, for the same reason as partner reviews: the
 * activity feed is built around an actor whose profile decorates the row, and a
 * kitchen is not a profile. The order itself is the record; the push opens it.
 *
 * <p>Not every transition is worth a phone lighting up. CONFIRMED arrives while
 * the customer is still looking at the screen that caused it, and
 * COURIER_TO_RESTAURANT is a detail nobody asked to be told about. What is left
 * is the three moments a person actually wants: the kitchen started, the food is
 * moving, it's here — plus a cancellation, which they need whether they want it
 * or not.
 */
@Component
class OrderNotificationListener {

    private final ApnsPushSender apns;

    OrderNotificationListener(ApnsPushSender apns) {
        this.apns = apns;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onStatusChanged(OrderStatusChanged event) {
        String merchant = event.merchantName() == null || event.merchantName().isBlank()
            ? "Your order" : event.merchantName();
        String title;
        String body;
        switch (event.status()) {
            case "PREPARING" -> {
                title = merchant + " is preparing your order";
                body = eta(event, "It'll be on its way shortly.");
            }
            case "DELIVERING" -> {
                title = "Your order is on the way";
                body = eta(event, "Your courier is heading to you.");
            }
            case "DELIVERED" -> {
                title = "Your order has arrived";
                body = "Enjoy. You can rate it — or tip your courier — in the app.";
            }
            case "CANCELLED" -> {
                title = "Your order was cancelled";
                body = "Anything you paid has gone straight back to your wallet.";
            }
            // Not one of the six order statuses: one kitchen's slice ended
            // while the rest of the order carries on (Phase 4 M3). A client
            // that predates it lands in the default arm and stays quiet.
            case "SUB_CANCELLED" -> {
                title = merchant + " couldn't take part of your order";
                body = "That part went straight back to your wallet — the rest is still coming.";
            }
            default -> {
                return;
            }
        }
        apns.notifySystem(event.userId(), title, body, "order", event.orderId());
    }

    private static String eta(OrderStatusChanged event, String fallback) {
        return event.etaMinutes() > 0
            ? "About %d min away.".formatted(event.etaMinutes())
            : fallback;
    }
}
