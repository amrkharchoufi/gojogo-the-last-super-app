package com.gojogo.messaging.internal;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Messaging's configuration. Every AWS client this module uses is built on
 * first call rather than as a bean here — {@link MessagingRepository} for
 * DynamoDB, {@link Fanout} for the {@code @connections} management API,
 * {@link WorldSmsSender} for SNS — because the SDK resolves a region
 * <em>eagerly</em>, at construction, and throws when it cannot find one. A bean
 * that did that would make an environment without messaging fail to start
 * instead of starting with messaging switched off.
 *
 * <p>{@code @EnableScheduling} lives here for historical reasons and is the
 * only one in the application: it switches on every {@code @Scheduled} method
 * in every module, not just this one's. It is why this class still exists.
 */
@Configuration
@EnableScheduling
@EnableConfigurationProperties(MessagingProperties.class)
class MessagingConfig {
}
