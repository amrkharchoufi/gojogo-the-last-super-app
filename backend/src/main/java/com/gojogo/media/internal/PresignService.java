package com.gojogo.media.internal;

import com.gojogo.media.MediaDocumentApi;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;

import java.time.Duration;
import java.util.Map;
import java.util.UUID;

@Service
@EnableConfigurationProperties(MediaProperties.class)
class PresignService implements MediaDocumentApi {

    private static final Duration EXPIRY = Duration.ofMinutes(15);

    /** Long enough for a reviewer to open the image, short enough that a URL
     *  pasted into a chat is dead by the time anyone else clicks it. */
    private static final Duration DOCUMENT_READ_EXPIRY = Duration.ofMinutes(10);

    /**
     * Private objects live outside {@code media/}, which is the exact prefix the
     * bucket policy publishes. Nothing here is world-readable, and the orphan
     * sweep — which also keys off {@code media/} — leaves it alone, so the row
     * that owns a document is responsible for deleting it.
     */
    private static final String PRIVATE_PREFIX = "private/";

    private static final Logger log = LoggerFactory.getLogger(PresignService.class);

    // Uploaded keys are content-addressed (media/{profile}/{randomUUID}.{ext}),
    // so an object never changes once written — cache it forever at every layer
    // (OS/URLCache, and CloudFront once the account is verified). Stamped at PUT
    // time; the client must replay this exact header (it is a signed header).
    static final String MEDIA_CACHE_CONTROL = "public, max-age=31536000, immutable";

    private static final Map<String, String> EXTENSION_BY_CONTENT_TYPE = Map.of(
        "image/jpeg", "jpg",
        "image/png", "png",
        "image/webp", "webp",
        "image/heic", "heic",
        "image/gif", "gif",
        "video/mp4", "mp4",
        "video/quicktime", "mov",
        // Voice notes recorded in My World (AAC in an MPEG-4 container).
        "audio/m4a", "m4a");

    /**
     * What a KYC document may be. Narrower than the public whitelist — no video
     * and no audio, because neither is a document — and wider by one: a
     * business licence usually arrives as a PDF.
     */
    private static final Map<String, String> DOCUMENT_EXTENSION_BY_CONTENT_TYPE = Map.of(
        "image/jpeg", "jpg",
        "image/png", "png",
        "image/heic", "heic",
        "application/pdf", "pdf");

    private final MediaProperties properties;
    private final MediaReferenceService references;

    // Built on first use, never at startup: S3Presigner.create() and
    // S3Client.create() resolve the region *eagerly* and throw when there is
    // none, which would stop the whole application from starting over a bucket
    // this environment may not have. Unconfigured is a mode here, not a failure.
    private volatile S3Presigner presigner;
    private volatile S3Client s3;

    PresignService(MediaProperties properties, MediaReferenceService references) {
        this.properties = properties;
        this.references = references;
        if (!properties.enabled()) {
            log.info("Media uploads are off (no MEDIA_BUCKET) — presign requests answer 503");
        }
    }

    private synchronized S3Presigner presigner() {
        requireConfigured();
        if (presigner == null) presigner = S3Presigner.create();
        return presigner;
    }

    private synchronized S3Client s3() {
        requireConfigured();
        if (s3 == null) s3 = S3Client.create();
        return s3;
    }

    private void requireConfigured() {
        if (!properties.enabled()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Media uploads aren't configured on this environment");
        }
    }

    PresignResponse presign(UUID profileId, String contentType) {
        String extension = EXTENSION_BY_CONTENT_TYPE.get(contentType);
        if (extension == null) {
            throw new ResponseStatusException(HttpStatus.UNSUPPORTED_MEDIA_TYPE,
                "Unsupported content type; use one of " + EXTENSION_BY_CONTENT_TYPE.keySet());
        }
        String key = "media/" + profileId + "/" + UUID.randomUUID() + "." + extension;
        PutObjectRequest put = PutObjectRequest.builder()
            .bucket(properties.bucket())
            .key(key)
            .contentType(contentType)
            .cacheControl(MEDIA_CACHE_CONTROL)
            .build();
        String uploadUrl = presigner().presignPutObject(PutObjectPresignRequest.builder()
                .signatureDuration(EXPIRY)
                .putObjectRequest(put)
                .build())
            .url()
            .toString();
        String publicUrl = "https://" + properties.cdnDomain() + "/" + key;
        // Record the key so the cleanup sweep can tell whether it is ever referenced.
        references.recordUpload(key, profileId, contentType);
        return new PresignResponse(uploadUrl, key, publicUrl, contentType,
            EXPIRY.toSeconds(), MEDIA_CACHE_CONTROL);
    }

    // MARK: Private documents (MediaDocumentApi)

    @Override
    public DocumentUpload presignDocumentUpload(UUID ownerId, String folder, String contentType) {
        String extension = DOCUMENT_EXTENSION_BY_CONTENT_TYPE.get(contentType);
        if (extension == null) {
            throw new ResponseStatusException(HttpStatus.UNSUPPORTED_MEDIA_TYPE,
                "Unsupported document type; use one of "
                    + DOCUMENT_EXTENSION_BY_CONTENT_TYPE.keySet());
        }
        String key = PRIVATE_PREFIX + slug(folder) + "/" + ownerId + "/"
            + UUID.randomUUID() + "." + extension;
        // No Cache-Control: unlike public media this is never meant to sit in a
        // cache, and every read is a fresh signature anyway.
        PutObjectRequest put = PutObjectRequest.builder()
            .bucket(properties.bucket())
            .key(key)
            .contentType(contentType)
            .build();
        String uploadUrl = presigner().presignPutObject(PutObjectPresignRequest.builder()
                .signatureDuration(EXPIRY)
                .putObjectRequest(put)
                .build())
            .url()
            .toString();
        // Deliberately not recorded as an upload: MediaCleanupJob only sweeps
        // the public prefix, and a document's lifetime is its owning row's.
        return new DocumentUpload(uploadUrl, key, contentType, EXPIRY.toSeconds());
    }

    @Override
    public String presignDocumentRead(String objectKey) {
        requirePrivate(objectKey);
        return presigner().presignGetObject(GetObjectPresignRequest.builder()
                .signatureDuration(DOCUMENT_READ_EXPIRY)
                .getObjectRequest(GetObjectRequest.builder()
                    .bucket(properties.bucket())
                    .key(objectKey)
                    .build())
                .build())
            .url()
            .toString();
    }

    @Override
    public void deleteDocument(String objectKey) {
        requirePrivate(objectKey);
        try {
            s3().deleteObject(DeleteObjectRequest.builder()
                .bucket(properties.bucket()).key(objectKey).build());
        } catch (RuntimeException e) {
            // Best-effort: the row is going regardless, and a stranded private
            // object is a cost problem, not a correctness one.
            log.warn("Could not delete private object {}: {}", objectKey, e.toString());
        }
    }

    /** Refuses to sign or delete anything outside the private area, so a caller
     *  can never turn this into a general-purpose handle on the bucket. */
    private static void requirePrivate(String objectKey) {
        if (objectKey == null || !objectKey.startsWith(PRIVATE_PREFIX) || objectKey.contains("..")) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such document");
        }
    }

    private static String slug(String folder) {
        String cleaned = folder == null ? "" : folder.replaceAll("[^a-z0-9-]", "");
        return cleaned.isBlank() ? "misc" : cleaned;
    }

    @PreDestroy
    void close() {
        if (presigner != null) presigner.close();
        if (s3 != null) s3.close();
    }
}
