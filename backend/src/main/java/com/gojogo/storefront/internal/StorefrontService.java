package com.gojogo.storefront.internal;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.gojogo.config.ConfigApi;
import com.gojogo.storefront.StorefrontApi;
import com.gojogo.storefront.StorefrontBlock;
import com.gojogo.storefront.StorefrontDocument;
import com.gojogo.storefront.StorefrontRefKind;
import com.gojogo.storefront.StorefrontReferenceCheck;
import com.gojogo.storefront.StorefrontSurface;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * The one implementation of {@link StorefrontApi}.
 *
 * <p>Reads and writes are deliberately asymmetric. A write validates every block
 * and refuses the document over anything it doesn't like; a read hands back
 * whatever it can parse and an empty page when it can't. That asymmetry is the
 * whole availability story for this feature: the decorative half of a commerce
 * page must never be able to take the functional half down with it.
 */
@Service
class StorefrontService implements StorefrontApi {

    private static final Logger log = LoggerFactory.getLogger(StorefrontService.class);

    /** SPECS §14 knobs. Defaults are compiled in, so an empty config table
     *  behaves identically to a populated one. */
    private static final String MAX_BLOCKS_KEY = "storefront.max.blocks";
    private static final int MAX_BLOCKS_DEFAULT = 24;
    private static final String MAX_REFS_KEY = "storefront.max.refs.per.block";
    private static final int MAX_REFS_DEFAULT = 24;

    private static final TypeReference<List<StorefrontBlock>> BLOCK_LIST =
        new TypeReference<>() {
        };

    private final StorefrontRepository documents;
    private final ObjectMapper json;
    private final ConfigApi config;

    StorefrontService(StorefrontRepository documents, ObjectMapper json, ConfigApi config) {
        this.documents = documents;
        this.json = json;
        this.config = config;
    }

    @Override
    @Transactional(readOnly = true)
    public StorefrontDocument documentFor(StorefrontSurface surface, UUID ownerId) {
        if (ownerId == null) {
            return StorefrontDocument.empty();
        }
        return documents.findBySurfaceAndOwnerId(surface.name(), ownerId)
            .map(this::toDocument)
            .orElseGet(StorefrontDocument::empty);
    }

    @Override
    @Transactional(readOnly = true)
    public Map<UUID, StorefrontDocument> documentsFor(StorefrontSurface surface, Set<UUID> ownerIds) {
        if (ownerIds == null || ownerIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, StorefrontDocument> out = new HashMap<>();
        for (StoredStorefront row : documents.findBySurfaceAndOwnerIdIn(surface.name(), ownerIds)) {
            out.put(row.getOwnerId(), toDocument(row));
        }
        return out;
    }

    @Override
    @Transactional
    public StorefrontDocument save(StorefrontSurface surface, UUID ownerId,
                                   List<StorefrontBlock> blocks,
                                   StorefrontReferenceCheck references) {
        List<StorefrontBlock> validated = StorefrontValidator.validate(surface, blocks,
            (int) config.number(MAX_BLOCKS_KEY, MAX_BLOCKS_DEFAULT),
            (int) config.number(MAX_REFS_KEY, MAX_REFS_DEFAULT));

        // Ownership before storage, and before the version bump: a document that
        // names someone else's dish is refused whole, not stored with the bad
        // block dropped. Silently editing what an author wrote is worse than
        // telling them no.
        StorefrontDocument candidate = new StorefrontDocument(0, validated, null);
        StorefrontReferenceCheck check = references == null
            ? StorefrontReferenceCheck.NONE : references;
        for (StorefrontRefKind kind : StorefrontRefKind.values()) {
            Set<UUID> ids = candidate.references(kind);
            if (!ids.isEmpty()) {
                check.check(kind, ids);
            }
        }

        StoredStorefront row = documents.findBySurfaceAndOwnerId(surface.name(), ownerId)
            .orElseGet(() -> new StoredStorefront(surface.name(), ownerId));
        row.rewrite(write(validated));
        return toDocument(documents.save(row));
    }

    // MARK: Serialization

    private String write(List<StorefrontBlock> blocks) {
        try {
            return json.writeValueAsString(blocks);
        } catch (Exception e) {
            // Unreachable in practice — the blocks are plain records this module
            // built itself — but a storefront save must not surface as a 500
            // with a Jackson stack trace.
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "That page couldn't be stored.");
        }
    }

    /**
     * A row that won't parse reads as an empty page and logs, rather than
     * throwing. The only way to get one is a rollback to a build that predates a
     * block type, and on that day a restaurant losing its header is a smaller
     * outage than a restaurant losing its menu.
     */
    private StorefrontDocument toDocument(StoredStorefront row) {
        try {
            return new StorefrontDocument(row.getDocVersion(),
                json.readValue(row.getBlocks(), BLOCK_LIST), row.getUpdatedAt());
        } catch (Exception e) {
            log.warn("Unreadable storefront for owner {} (version {}): {}",
                row.getOwnerId(), row.getDocVersion(), e.toString());
            return StorefrontDocument.empty();
        }
    }
}
