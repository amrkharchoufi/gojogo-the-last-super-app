package com.gojogo.media.internal;

import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.data.domain.Limit;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.Delete;
import software.amazon.awssdk.services.s3.model.DeleteObjectsRequest;
import software.amazon.awssdk.services.s3.model.ObjectIdentifier;

import java.time.OffsetDateTime;
import java.util.List;

/**
 * Daily orphan-upload sweep. Finds presigned keys that were never referenced by
 * a post/story/avatar/message within the grace period and, when deletion is
 * enabled, removes them from S3 and from the tracking table.
 *
 * <p><b>Safe by default:</b> {@code gojogo.media.cleanup.delete} is false, so out
 * of the box this only logs what it <i>would</i> delete. Watch those logs after
 * deploying — any real, in-use media showing up as a candidate means a reference
 * write-point is not calling {@link com.gojogo.media.MediaApi#markReferenced},
 * and must be fixed before enabling deletion.
 */
@Component
@EnableConfigurationProperties(MediaCleanupProperties.class)
class MediaCleanupJob {

    private static final Logger log = LoggerFactory.getLogger(MediaCleanupJob.class);

    private final UploadObjectRepository uploads;
    private final MediaProperties media;
    private final MediaCleanupProperties config;
    private final S3Client s3 = S3Client.create();

    MediaCleanupJob(UploadObjectRepository uploads, MediaProperties media, MediaCleanupProperties config) {
        this.uploads = uploads;
        this.media = media;
        this.config = config;
    }

    // Daily at 03:30 UTC. Off-peak; the partial index keeps the query cheap.
    @Scheduled(cron = "0 30 3 * * *")
    void sweep() {
        if (!config.enabled()) {
            return;
        }
        try {
            runSweep();
        } catch (RuntimeException e) {
            log.warn("Media orphan sweep failed: {}", e.toString());
        }
    }

    @Transactional
    void runSweep() {
        OffsetDateTime cutoff = OffsetDateTime.now().minusHours(config.minAgeHours());
        List<UploadObject> orphans = uploads.findByReferencedAtIsNullAndCreatedAtBeforeOrderByCreatedAtAsc(
            cutoff, Limit.of(config.batchSize()));
        if (orphans.isEmpty()) {
            return;
        }
        List<String> keys = orphans.stream().map(UploadObject::getObjectKey).toList();

        if (!config.delete()) {
            log.info("Media orphan sweep (report-only): {} unreferenced upload(s) older than {}h "
                    + "would be deleted. Set gojogo.media.cleanup.delete=true to enable. Sample: {}",
                keys.size(), config.minAgeHours(), keys.subList(0, Math.min(keys.size(), 10)));
            return;
        }

        deleteFromS3(keys);
        uploads.deleteByObjectKeyIn(keys);
        log.info("Media orphan sweep deleted {} unreferenced upload(s) older than {}h.",
            keys.size(), config.minAgeHours());
    }

    private void deleteFromS3(List<String> keys) {
        List<ObjectIdentifier> ids = keys.stream()
            .map(k -> ObjectIdentifier.builder().key(k).build())
            .toList();
        s3.deleteObjects(DeleteObjectsRequest.builder()
            .bucket(media.bucket())
            .delete(Delete.builder().objects(ids).quiet(true).build())
            .build());
    }

    @PreDestroy
    void close() {
        s3.close();
    }
}
