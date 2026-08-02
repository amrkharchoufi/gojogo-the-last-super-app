package com.gojogo.messaging.internal;

import com.gojogo.media.MediaApi;
import com.gojogo.messaging.internal.MessagingRepository.StoredContent;
import com.gojogo.messaging.internal.MessagingRepository.WorldProfile;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * GojoMessages content: posts, stories and carousels published to the author's
 * contacts or to named circles.
 *
 * <p>This is a <em>second</em> content system, deliberately not {@code social}'s.
 * The reason is one sentence long: a GojoMessages post can never become public,
 * so folding it into {@code social} behind an audience column would make every
 * feed, profile grid, search and moderation read in that module responsible for
 * a phone graph it cannot see — and one missed {@code WHERE} clause would
 * publish somebody's private post to the world.
 *
 * <p>The safety property here is structural rather than diligent: content is
 * <b>fanned out on write</b> to exactly the resolved audience, and a reader only
 * ever queries their own feed partition. There is no audience filter on the read
 * path, so there is none to forget. Reading somebody's content directly (the
 * contact page tab) is answered from the <em>viewer's</em> partition too, for the
 * same reason — it returns what they were actually given, never what they might
 * be entitled to.
 */
@Service
class WorldContentService {

    /** Instagram's 24 hours. Stories are swept by DynamoDB TTL and re-filtered on read. */
    private static final Duration STORY_TTL = Duration.ofHours(24);
    private static final int PAGE = 100;

    private final MessagingRepository repo;
    private final WorldGraphService graph;
    private final MediaApi media;

    WorldContentService(MessagingRepository repo, WorldGraphService graph, MediaApi media) {
        this.repo = repo;
        this.graph = graph;
        this.media = media;
    }

    // ---- publishing -------------------------------------------------------

    WorldContentDto publish(UUID authorId, PublishContentRequest req) {
        String kind = normalizeKind(req.kind());
        requireSetup(authorId);
        Instant now = Instant.now();
        StoredContent content = new StoredContent(
            UUID.randomUUID(), authorId, kind, trimmed(req.text()),
            req.mediaItems() == null ? List.of() : req.mediaItems(),
            now,
            "story".equals(kind) ? now.plus(STORY_TTL) : null,
            req.audience().name(),
            req.circleIds() == null ? List.of() : req.circleIds());

        if ((content.text() == null || content.text().isBlank()) && content.mediaItems().isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "A post needs words or something to look at");
        }

        Set<UUID> viewers = graph.resolveAudience(authorId, req.audience(), req.circleIds());
        repo.publishContent(content, new ArrayList<>(viewers));
        markMediaReferenced(content);
        return toDto(content, authorId, true, false);
    }

    void delete(UUID authorId, UUID contentId) {
        StoredContent content = repo.getContent(authorId, contentId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such post"));
        // Re-resolved rather than remembered: the fan-out list isn't stored, and
        // a stale copy left in somebody's feed would outlive the delete.
        Set<UUID> viewers = graph.resolveAudience(authorId,
            WorldAudience.valueOf(content.audience()), content.circleIds());
        repo.deleteContent(content, new ArrayList<>(viewers));
    }

    // ---- reading ----------------------------------------------------------

    /** The home screen in one round trip: a stories row, then posts. */
    WorldFeedDto feed(UUID viewerId) {
        Set<UUID> seen = repo.seenStories(viewerId);
        List<WorldContentDto> posts = new ArrayList<>();
        for (StoredContent c : repo.feed(viewerId, "post", PAGE)) {
            posts.add(toDto(c, viewerId, false, false));
        }
        return new WorldFeedDto(storyGroups(repo.feed(viewerId, "story", PAGE), viewerId, seen), posts);
    }

    /** Your own posts, for your grid. Includes the audience — it's yours to see. */
    List<WorldContentDto> mine(UUID authorId, String kind) {
        List<WorldContentDto> out = new ArrayList<>();
        for (StoredContent c : repo.contentBy(authorId, normalizeKind(kind), PAGE)) {
            out.add(toDto(c, authorId, true, true));
        }
        return out;
    }

    /**
     * What one person has published <em>to you</em> — the contact page tab.
     *
     * <p>Answered from the viewer's own feed partition rather than from the
     * author's, so it can only ever return content the author actually sent this
     * viewer. Asking the author's partition and filtering would give the same
     * answer on a good day and leak on a bad one.
     */
    List<WorldContentDto> byAuthorForViewer(UUID viewerId, UUID authorId, String kind) {
        if (viewerId.equals(authorId)) return mine(authorId, kind);
        List<WorldContentDto> out = new ArrayList<>();
        for (StoredContent c : repo.feed(viewerId, normalizeKind(kind), PAGE)) {
            if (!c.authorId().equals(authorId)) continue;
            out.add(toDto(c, viewerId, false, false));
        }
        return out;
    }

    void markSeen(UUID viewerId, UUID contentId) {
        repo.markStorySeen(viewerId, contentId);
    }

    // ---- helpers ----------------------------------------------------------

    private List<WorldStoryGroupDto> storyGroups(List<StoredContent> stories, UUID viewerId,
                                                 Set<UUID> seen) {
        // Grouped by author, newest author first, frames oldest-first inside the
        // group — which is the order a story row is tapped through.
        Map<UUID, List<StoredContent>> byAuthor = new LinkedHashMap<>();
        for (StoredContent c : stories) {
            byAuthor.computeIfAbsent(c.authorId(), k -> new ArrayList<>()).add(c);
        }
        List<WorldStoryGroupDto> out = new ArrayList<>();
        for (var entry : byAuthor.entrySet()) {
            List<StoredContent> frames = new ArrayList<>(entry.getValue());
            frames.sort(java.util.Comparator.comparing(StoredContent::createdAt));
            boolean allSeen = frames.stream().allMatch(f -> seen.contains(f.id()));
            List<WorldContentDto> dtos = new ArrayList<>();
            for (StoredContent f : frames) {
                dtos.add(toDto(f, viewerId, false, seen.contains(f.id())));
            }
            WorldProfile p = repo.getWorldProfile(entry.getKey()).orElse(null);
            out.add(new WorldStoryGroupDto(entry.getKey(),
                p != null ? p.displayName() : null,
                p != null ? p.avatarUrl() : null,
                allSeen, dtos));
        }
        return out;
    }

    /**
     * @param isAuthor whether the caller wrote it — decides if the audience they
     *                 picked comes back with it. A reader has no business knowing
     *                 which of the author's circles they landed in.
     */
    private WorldContentDto toDto(StoredContent c, UUID viewerId, boolean isAuthor, boolean seen) {
        WorldProfile p = repo.getWorldProfile(c.authorId()).orElse(null);
        // The real name travels; the viewer's private rename is applied on the
        // client, keyed by authorId (see ARCHITECTURE Phase 2f M1).
        WorldContentDto dto = new WorldContentDto(
            c.id(), c.authorId(),
            p != null ? p.displayName() : null,
            p != null ? p.avatarUrl() : null,
            c.kind(), c.text(), c.mediaItems(), c.createdAt(), c.expiresAt(), seen,
            c.audience() == null ? null : WorldAudience.valueOf(c.audience()),
            c.circleIds());
        return isAuthor ? dto : dto.withoutAudience();
    }

    private void requireSetup(UUID authorId) {
        WorldProfile p = repo.getWorldProfile(authorId).orElse(null);
        if (p == null || !p.setupComplete()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Finish setting up GojoMessages first");
        }
    }

    private void markMediaReferenced(StoredContent c) {
        List<String> urls = new ArrayList<>();
        for (MediaItemDto item : c.mediaItems()) {
            if (item.imageUrl() != null && !item.imageUrl().isBlank()) urls.add(item.imageUrl());
            if (item.videoUrl() != null && !item.videoUrl().isBlank()) urls.add(item.videoUrl());
        }
        if (!urls.isEmpty()) media.markReferenced(urls);
    }

    private static String normalizeKind(String raw) {
        if (raw == null) return "post";
        return switch (raw.toLowerCase()) {
            case "story" -> "story";
            case "carousel" -> "carousel";
            default -> "post";
        };
    }

    private static String trimmed(String in) {
        return in == null ? null : in.trim();
    }
}
