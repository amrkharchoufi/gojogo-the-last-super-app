package com.gojogo.notifications.internal;

import com.gojogo.delivery.OrderPlaced;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * Tells a restaurant an order is waiting — the consumer {@code OrderPlaced} has
 * been publishing into the void since 2b M4.
 *
 * <p>It arrives with real couriers rather than earlier because until now nobody
 * had to be told: a simulated fulfilment job started cooking on its own twenty
 * seconds after checkout. Now a kitchen that never looks at their tablet is an
 * order that times out, a customer whose money sat in escrow for ten minutes,
 * and a dinner nobody made. This is the only thing standing between those two
 * facts.
 *
 * <p>Push only, no activity row, for the same reason order status changes are:
 * the activity feed is built around an actor whose profile decorates the row,
 * and a customer's basket is not an actor. The order queue is the record; the
 * push opens it.
 */
@Component
class NewOrderNotificationListener {

    private final ApnsPushSender apns;

    NewOrderNotificationListener(ApnsPushSender apns) {
        this.apns = apns;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onOrderPlaced(OrderPlaced event) {
        if (event.merchantOwnerId() == null) return;
        apns.notifySystem(event.merchantOwnerId(), "New order",
            "Accept it in your dashboard so a courier can be found in time.",
            "merchant-order", event.orderId());
    }
}
