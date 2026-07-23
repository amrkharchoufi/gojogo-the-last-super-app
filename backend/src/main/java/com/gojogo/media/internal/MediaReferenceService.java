package com.gojogo.media.internal;

import com.gojogo.media.MediaApi;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.net.URI;
import java.time.OffsetDateTime;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.UUID;

/**
 * Tracks presigned uploads and, via {@link MediaApi}, marks the ones that end up
 * referenced. The stored identity is the S3 object key; public URLs are mapped
 * back to keys by their path, so a CDN-domain change does not break matching.
 */
@Service
class MediaReferenceService implements MediaApi {

    private final UploadObjectRepository uploads;

    MediaReferenceService(UploadObjectRepository uploads) {
        this.uploads = uploads;
    }

    /** Called by {@link PresignService} for every key it mints. */
    @Transactional
    void recordUpload(String objectKey, UUID profileId, String contentType) {
        uploads.save(new UploadObject(objectKey, profileId, contentType, OffsetDateTime.now()));
    }

    @Override
    @Transactional
    public void markReferenced(Collection<String> urls) {
        if (urls == null || urls.isEmpty()) {
            return;
        }
        Set<String> keys = new LinkedHashSet<>();
        for (String url : urls) {
            String key = keyFor(url);
            if (key != null) {
                keys.add(key);
            }
        }
        if (!keys.isEmpty()) {
            uploads.markReferenced(keys, OffsetDateTime.now());
        }
    }

    /** Extracts the object key ("media/…") from a public URL, or null if it isn't one of ours. */
    static String keyFor(String url) {
        if (url == null || url.isBlank()) {
            return null;
        }
        try {
            String path = URI.create(url.trim()).getPath();
            if (path == null || path.isBlank()) {
                return null;
            }
            String key = path.startsWith("/") ? path.substring(1) : path;
            return key.startsWith("media/") ? key : null;
        } catch (RuntimeException e) {
            return null;
        }
    }
}
