package com.gojogo.messaging.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Bound from MESSAGING_TABLE / MESSAGING_WS_ENDPOINT env vars (see
 * application.yml). {@code table} is the DynamoDB single-table name;
 * {@code wsEndpoint} is the API Gateway {@code @connections} management URL
 * ({@code https://{apiId}.execute-api.{region}.amazonaws.com/{stage}}) the
 * backend POSTs to for server->client fan-out. Both empty in local dev, where
 * messaging endpoints simply fail at call time (nothing else depends on them).
 */
@ConfigurationProperties(prefix = "gojogo.messaging")
record MessagingProperties(String table, String wsEndpoint) {

    /** False when no table is configured: messaging is off, not broken — see
     *  {@link MessagingRepository}, which builds no DynamoDB client at all. */
    boolean enabled() {
        return table != null && !table.isBlank();
    }

    boolean fanoutEnabled() {
        return wsEndpoint != null && !wsEndpoint.isBlank();
    }
}
