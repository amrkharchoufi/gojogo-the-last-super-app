package com.gojogo.economy.internal;

import com.gojogo.config.ConfigApi;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.data.domain.PageRequest;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Settles the shipped orders nobody ever confirmed.
 *
 * <p>Settlement waits for the buyer's tap, and most buyers never tap — a parcel
 * that arrived is a parcel forgotten. Without this sweep the seller's money
 * sits in the buyer's escrow forever, hostage to a button. After
 * {@code economy.order.autocomplete.days} (CONFIG, 14) the parcel is presumed
 * received and the settlement runs — the same presumption every marketplace
 * makes, and generous enough that a genuinely lost parcel has long since become
 * a support conversation.
 */
@Component
class ProductOrderAutoCompleteJob {

    private static final Logger log = LoggerFactory.getLogger(ProductOrderAutoCompleteJob.class);
    private static final int BATCH = 100;

    private final ProductOrderRepository orders;
    private final ProductCheckoutService checkout;
    private final ConfigApi config;

    ProductOrderAutoCompleteJob(ProductOrderRepository orders,
                                ProductCheckoutService checkout, ConfigApi config) {
        this.orders = orders;
        this.checkout = checkout;
        this.config = config;
    }

    @Scheduled(fixedDelayString = "${gojogo.economy.autocomplete-poll-ms:3600000}")
    void tick() {
        long days = Math.max(1, config.number("economy.order.autocomplete.days", 14));
        OffsetDateTime cutoff = OffsetDateTime.now().minusDays(days);
        for (UUID orderId : orders.shippedBefore(cutoff, PageRequest.of(0, BATCH))) {
            try {
                checkout.completeShipped(orderId);
            } catch (OptimisticLockingFailureException anotherInstanceGotThere) {
                // the winner's completion stands
            } catch (Exception e) {
                log.error("Auto-complete of product order {} failed", orderId, e);
            }
        }
    }
}
