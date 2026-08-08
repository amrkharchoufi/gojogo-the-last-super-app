package com.gojogo.assistant.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Where the model lives and what it is called (MADELEINE-INFERENCE.md §5's
 * CONFIG surface).
 *
 * <p>Infrastructure, not policy: these are here rather than in the config
 * registry because changing the inference endpoint is a deploy-shaped decision,
 * while the loop's budgets — how many steps, how long, how many items — are
 * policy and are read from {@link com.gojogo.config.ConfigApi} at the point of
 * use.
 *
 * <p><b>No secret, and deliberately so.</b> Bedrock is reached with SigV4 under
 * the Fargate task role — the task role <em>is</em> the credential. That makes
 * this the one integration in this codebase that cannot ship half-configured:
 * there is no {@code -c …SecretArn} flag to forget, and therefore no repeat of
 * the 2026-07-30 silently-disabled-module failure.
 *
 * <p><b>The grant it needs is not the grant it has.</b> Measured against the
 * live endpoint on 2026-08-08: a correctly signed request to the
 * {@code bedrock-mantle} Chat Completions path is refused with
 * {@code not authorized to perform: bedrock-mantle:CreateInference on resource:
 * arn:aws:bedrock-mantle:<region>:<account>:project/default}. It does
 * <em>not</em> authorize as {@code bedrock:InvokeModel} on a foundation-model
 * ARN, which is what infra/lib/fargate-stack.ts grants and what
 * MADELEINE-INFERENCE.md §10 item 2 asserts covers it. That statement needs
 * replacing before a deploy of this module does anything at all.
 *
 * @param baseUrl         OpenAI-compatible base, ending before {@code /chat/completions}
 * @param sidekickBaseUrl blank means "same host as the brain", which is true on
 *                        Bedrock and false on a self-hosted split (§2 gives the
 *                        sidekick its own node)
 * @param sigv4           false for an endpoint that wants no credential at all —
 *                        a vLLM behind the internal ALB, reachable only from the
 *                        Fargate security group. Not an API-key switch: there is
 *                        no API key anywhere in this module
 */
@ConfigurationProperties(prefix = "gojogo.assistant.model")
record AssistantModelProperties(String baseUrl, String name,
                                String sidekickBaseUrl, String sidekickName,
                                String region, String signingName, boolean sigv4,
                                int timeoutSeconds, int maxOutputTokens) {

    /** True once an endpoint is configured. Everything empty means Madeleine is
     *  off, and the module says so rather than failing per request. */
    boolean configured() {
        return baseUrl != null && !baseUrl.isBlank() && name != null && !name.isBlank();
    }

    String baseUrlFor(AssistantModelRole role) {
        if (role == AssistantModelRole.SIDEKICK
            && sidekickBaseUrl != null && !sidekickBaseUrl.isBlank()) {
            return trimmed(sidekickBaseUrl);
        }
        return trimmed(baseUrl);
    }

    String nameFor(AssistantModelRole role) {
        if (role == AssistantModelRole.SIDEKICK
            && sidekickName != null && !sidekickName.isBlank()) {
            return sidekickName;
        }
        return name;
    }

    private static String trimmed(String url) {
        return url.endsWith("/") ? url.substring(0, url.length() - 1) : url;
    }
}
