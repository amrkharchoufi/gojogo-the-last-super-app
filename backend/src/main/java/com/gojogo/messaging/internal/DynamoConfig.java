package com.gojogo.messaging.internal;

import jakarta.annotation.PreDestroy;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

/**
 * DynamoDB client for the messaging single table. Region + credentials come
 * from the default provider chain (App Runner instance role in prod). The
 * {@code @connections} client is built lazily per fan-out because its endpoint
 * is the WebSocket management URL, not the regional DynamoDB endpoint.
 */
@Configuration
@EnableScheduling
@EnableConfigurationProperties(MessagingProperties.class)
class DynamoConfig {

    private DynamoDbClient client;

    @Bean
    DynamoDbClient dynamoDbClient() {
        client = DynamoDbClient.create();
        return client;
    }

    @PreDestroy
    void close() {
        if (client != null) {
            client.close();
        }
    }
}
