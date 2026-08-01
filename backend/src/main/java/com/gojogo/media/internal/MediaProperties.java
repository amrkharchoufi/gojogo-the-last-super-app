package com.gojogo.media.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Bound from MEDIA_BUCKET / MEDIA_CDN_DOMAIN env vars (see application.yml).
 */
@ConfigurationProperties(prefix = "gojogo.media")
record MediaProperties(String bucket, String cdnDomain) {

    /** False when no bucket is configured: uploads are off, not broken — no S3
     *  client is built, and the presign endpoints answer 503. */
    boolean enabled() {
        return bucket != null && !bucket.isBlank();
    }
}
