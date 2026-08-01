package com.gojogo.messaging.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Delivers due send-later messages. Polls every 30s; each due message is claimed
 * with a conditional delete so that if App Runner runs more than one instance,
 * exactly one delivers it.
 */
@Component
@EnableConfigurationProperties(MessagingProperties.class)
class ScheduledDeliveryJob {

    private static final Logger log = LoggerFactory.getLogger(ScheduledDeliveryJob.class);

    private final MessagingService messaging;
    private final MessagingProperties props;

    ScheduledDeliveryJob(MessagingService messaging, MessagingProperties props) {
        this.messaging = messaging;
        this.props = props;
    }

    @Scheduled(fixedDelay = 30_000, initialDelay = 20_000)
    void deliverDue() {
        // Where messaging is off there is no table to poll, and a pass would do
        // nothing but log its own 503 twice a minute.
        if (!props.enabled()) return;
        try {
            messaging.deliverDueScheduled();
        } catch (RuntimeException e) {
            log.warn("Scheduled message delivery pass failed: {}", e.toString());
        }
    }
}
