package com.gojogo.messaging.internal;

import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.MessageAttributeValue;
import software.amazon.awssdk.services.sns.model.PublishRequest;

import java.util.Map;

/**
 * Delivers the My World verification code by SMS via SNS. Best-effort: if SMS is
 * disabled or SNS rejects the send (new-account SNS SMS sandbox only allows
 * verified destination numbers), we log and return false — the caller still
 * stores the code, and the {@code devOtpCode} fallback keeps the flow testable.
 */
@Component
@EnableConfigurationProperties(WorldProperties.class)
class WorldSmsSender {

    private static final Logger log = LoggerFactory.getLogger(WorldSmsSender.class);

    private final WorldProperties props;
    private SnsClient sns;

    WorldSmsSender(WorldProperties props) {
        this.props = props;
    }

    private SnsClient sns() {
        if (sns == null) sns = SnsClient.create();
        return sns;
    }

    /** @return true if SNS accepted the message. */
    boolean sendCode(String e164Phone, String code) {
        if (!props.smsEnabled()) {
            log.info("World SMS disabled; code for {} is {}", e164Phone, code);
            return false;
        }
        try {
            Map<String, MessageAttributeValue> attrs = new java.util.HashMap<>();
            attrs.put("AWS.SNS.SMS.SMSType", MessageAttributeValue.builder()
                .dataType("String").stringValue("Transactional").build());
            if (props.smsSenderId() != null && !props.smsSenderId().isBlank()) {
                attrs.put("AWS.SNS.SMS.SenderID", MessageAttributeValue.builder()
                    .dataType("String").stringValue(props.smsSenderId()).build());
            }
            sns().publish(PublishRequest.builder()
                .phoneNumber(e164Phone)
                .message("Your GojoGo My World code is " + code)
                .messageAttributes(attrs)
                .build());
            return true;
        } catch (RuntimeException e) {
            log.warn("World SMS send to {} failed ({}); code is {}", e164Phone, e.toString(), code);
            return false;
        }
    }

    @PreDestroy
    void close() {
        if (sns != null) sns.close();
    }
}
