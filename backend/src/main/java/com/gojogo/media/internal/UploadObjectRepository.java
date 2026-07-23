package com.gojogo.media.internal;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.Collection;
import java.util.List;

interface UploadObjectRepository extends JpaRepository<UploadObject, String> {

    /** Stamp the given keys as referenced (only the ones still unreferenced). */
    @Modifying
    @Query("update UploadObject u set u.referencedAt = :now "
        + "where u.objectKey in :keys and u.referencedAt is null")
    int markReferenced(@Param("keys") Collection<String> keys, @Param("now") OffsetDateTime now);

    /** Oldest still-unreferenced uploads created before the cutoff — the orphan candidates. */
    List<UploadObject> findByReferencedAtIsNullAndCreatedAtBeforeOrderByCreatedAtAsc(
        OffsetDateTime cutoff, Limit limit);

    void deleteByObjectKeyIn(Collection<String> keys);
}
