package com.gojogo.media.internal;

import jakarta.annotation.PreDestroy;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;

import java.time.Duration;
import java.util.Map;
import java.util.UUID;

@Service
@EnableConfigurationProperties(MediaProperties.class)
class PresignService {

    private static final Duration EXPIRY = Duration.ofMinutes(15);

    private static final Map<String, String> EXTENSION_BY_CONTENT_TYPE = Map.of(
        "image/jpeg", "jpg",
        "image/png", "png",
        "image/webp", "webp",
        "image/heic", "heic",
        "image/gif", "gif",
        "video/mp4", "mp4",
        "video/quicktime", "mov");

    private final MediaProperties properties;
    private final S3Presigner presigner = S3Presigner.create();

    PresignService(MediaProperties properties) {
        this.properties = properties;
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
            .build();
        String uploadUrl = presigner.presignPutObject(PutObjectPresignRequest.builder()
                .signatureDuration(EXPIRY)
                .putObjectRequest(put)
                .build())
            .url()
            .toString();
        String publicUrl = "https://" + properties.cdnDomain() + "/" + key;
        return new PresignResponse(uploadUrl, key, publicUrl, contentType, EXPIRY.toSeconds());
    }

    @PreDestroy
    void close() {
        presigner.close();
    }
}
