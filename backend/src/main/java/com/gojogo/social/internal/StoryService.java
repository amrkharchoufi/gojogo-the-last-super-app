package com.gojogo.social.internal;

import com.gojogo.media.MediaApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
class StoryService {

    private final StoryFrameRepository frames;
    private final StoryViewRepository views;
    private final FollowRepository follows;
    private final ProfileApi profiles;
    private final MediaApi media;

    StoryService(StoryFrameRepository frames, StoryViewRepository views,
                 FollowRepository follows, ProfileApi profiles, MediaApi media) {
        this.frames = frames;
        this.views = views;
        this.follows = follows;
        this.profiles = profiles;
        this.media = media;
    }

    @Transactional
    List<StoryFrameDto> create(UUID me, List<String> frameImageUrls) {
        List<StoryFrameDto> created = new ArrayList<>();
        for (String url : frameImageUrls) {
            StoryFrame frame = frames.save(new StoryFrame(me, url));
            created.add(new StoryFrameDto(frame.getId(), frame.getImageUrl(), false, frame.getCreatedAt()));
        }
        media.markReferenced(frameImageUrls);
        return created;
    }

    /**
     * Story rings for the home rail: own ring first, then followed users',
     * unexpired frames only, ordered oldest-first within a ring.
     */
    @Transactional(readOnly = true)
    List<StoryRingResponse> rings(UUID me) {
        Set<UUID> authorIds = new java.util.HashSet<>(follows.followeeIds(me));
        authorIds.add(me);
        List<StoryFrame> active = frames.findByAuthorIdInAndExpiresAtAfterOrderByCreatedAtAsc(
            authorIds, OffsetDateTime.now());
        if (active.isEmpty()) {
            return List.of();
        }
        Set<UUID> frameIds = active.stream().map(StoryFrame::getId).collect(Collectors.toSet());
        Set<UUID> seen = views.viewedFrameIds(me, frameIds);
        Map<UUID, List<StoryFrame>> byAuthor = active.stream()
            .collect(Collectors.groupingBy(StoryFrame::getAuthorId, LinkedHashMap::new, Collectors.toList()));
        Map<UUID, ProfileDto> authors = profiles.findByIds(byAuthor.keySet());

        List<StoryRingResponse> rings = new ArrayList<>();
        byAuthor.forEach((authorId, authorFrames) -> {
            ProfileDto author = authors.get(authorId);
            String name = author == null ? "Deleted user"
                : author.displayName() != null ? author.displayName() : author.handle();
            rings.add(new StoryRingResponse(
                authorId,
                name,
                author == null ? null : author.handle(),
                author == null ? null : author.avatarUrl(),
                authorId.equals(me),
                authorFrames.stream()
                    .map(f -> new StoryFrameDto(f.getId(), f.getImageUrl(),
                        seen.contains(f.getId()), f.getCreatedAt()))
                    .toList()));
        });
        rings.sort((a, b) -> Boolean.compare(b.isYou(), a.isYou()));
        return rings;
    }

    @Transactional
    void markSeen(UUID me, UUID frameId) {
        if (!frames.existsById(frameId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such story frame");
        }
        try {
            views.saveAndFlush(new StoryView(frameId, me));
        } catch (DataIntegrityViolationException alreadySeen) {
            // idempotent
        }
    }
}
