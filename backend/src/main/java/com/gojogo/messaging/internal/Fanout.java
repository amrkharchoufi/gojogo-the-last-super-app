package com.gojogo.messaging.internal;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.apigatewaymanagementapi.ApiGatewayManagementApiClient;
import software.amazon.awssdk.services.apigatewaymanagementapi.model.GoneException;

import java.net.URI;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Server->client delivery over the API Gateway WebSocket, via the
 * {@code @connections} management API. The backend looks up each recipient's
 * live connection ids (registered by the $connect Lambda) and POSTs the event
 * JSON to them; a 410 Gone means the socket died without a clean $disconnect,
 * so the stale registry row is pruned. Fan-out is best-effort and never fails
 * the originating request — the durable write already succeeded.
 */
@Component
@EnableConfigurationProperties(MessagingProperties.class)
class Fanout {

    private static final Logger log = LoggerFactory.getLogger(Fanout.class);

    private final MessagingRepository repo;
    private final ProfileApi profiles;
    private final ObjectMapper json;
    private final MessagingProperties props;
    private ApiGatewayManagementApiClient client;

    Fanout(MessagingRepository repo, ProfileApi profiles, ObjectMapper json, MessagingProperties props) {
        this.repo = repo;
        this.profiles = profiles;
        this.json = json;
        this.props = props;
    }

    private ApiGatewayManagementApiClient client() {
        if (client == null) {
            client = ApiGatewayManagementApiClient.builder()
                .endpointOverride(URI.create(props.wsEndpoint()))
                .build();
        }
        return client;
    }

    /** Publish an event to every live connection of each recipient profile. */
    void publish(List<UUID> recipients, Map<String, Object> event) {
        if (!props.fanoutEnabled() || recipients.isEmpty()) return;
        SdkBytes payload;
        try {
            payload = SdkBytes.fromByteArray(json.writeValueAsBytes(event));
        } catch (Exception e) {
            log.warn("messaging fan-out serialize failed", e);
            return;
        }
        // Connections are registered by Cognito subject (all the $connect Lambda
        // has); bridge each recipient profile id to its subject here.
        Map<UUID, ProfileDto> people = profiles.findByIds(recipients);
        for (UUID profileId : recipients) {
            ProfileDto p = people.get(profileId);
            if (p == null || p.cognitoSub() == null) continue;
            String sub = p.cognitoSub();
            for (String connectionId : repo.connectionsForSub(sub)) {
                try {
                    client().postToConnection(b -> b.connectionId(connectionId).data(payload));
                } catch (GoneException gone) {
                    repo.removeConnection(sub, connectionId);
                } catch (RuntimeException e) {
                    log.debug("messaging fan-out to {} failed: {}", connectionId, e.toString());
                }
            }
        }
    }

    @PreDestroy
    void close() {
        if (client != null) client.close();
    }
}
