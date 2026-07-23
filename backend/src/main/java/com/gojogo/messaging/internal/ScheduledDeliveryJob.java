package com.gojogo.messaging.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Delivers due send-later messages. Polls every 30s; each due message is claimed
 * with a conditional delete so that if App Runner runs more than one instance,
 * exactly one delivers it.
 */
@Component
class ScheduledDeliveryJob {

    private static final Logger log = LoggerFactory.getLogger(ScheduledDeliveryJob.class);

    private final MessagingService messaging;

    ScheduledDeliveryJob(MessagingService messaging) {
        this.messaging = messaging;
    }

    @Scheduled(fixedDelay = 30_000, initialDelay = 20_000)
    void deliverDue() {
        try {
            messaging.deliverDueScheduled();
        } catch (RuntimeException e) {
            log.warn("Scheduled message delivery pass failed: {}", e.toString());
        }
    }
}
