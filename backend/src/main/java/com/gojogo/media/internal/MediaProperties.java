package com.gojogo.media.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Bound from MEDIA_BUCKET / MEDIA_CDN_DOMAIN env vars (see application.yml).
 */
@ConfigurationProperties(prefix = "gojogo.media")
record MediaProperties(String bucket, String cdnDomain) {
}
