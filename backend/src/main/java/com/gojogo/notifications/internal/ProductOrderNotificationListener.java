package com.gojogo.notifications.internal;

import com.gojogo.economy.ProductOrderPlaced;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * Tells a seller an order landed in their queue — the economy sibling of
 * {@code NewOrderNotificationListener}, and push-only for the same reason: a
 * buyer's basket is not an actor for the activity feed, and the order queue is
 * the record.
 */
@Component
class ProductOrderNotificationListener {

    private final ApnsPushSender apns;

    ProductOrderNotificationListener(ApnsPushSender apns) {
        this.apns = apns;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onProductOrderPlaced(ProductOrderPlaced event) {
        if (event.sellerOwnerId() == null) return;
        apns.notifySystem(event.sellerOwnerId(), "New order",
            event.itemCount() == 1
                ? "An item was just bought from your shop."
                : event.itemCount() + " items were just bought from your shop.",
            "seller-order", event.orderId());
    }
}
