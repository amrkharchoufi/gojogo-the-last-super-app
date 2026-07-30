package com.gojogo.social.internal;

import com.gojogo.media.MediaApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * What outlives the 24 hours: your archive, the highlights you pin to your
 * profile, and the close-friends list that decides who a restricted frame was
 * ever visible to.
 *
 * <p>Close friends is enforced on read, not on write: a frame posted to close
 * friends stays restricted forever, so removing someone from the list also
 * removes their access to the archive and highlight copies of it.
 */
@Service
class StoryHighlightService {

    private static final int MAX_ARCHIVE = 200;

    private final StoryFrameRepository frames;
    private final StoryHighlightRepository highlights;
    private final StoryHighlightFrameRepository highlightFrames;
    private final CloseFriendRepository closeFriends;
    private final StoryViewRepository views;
    private final ProfileApi profiles;
    private final MediaApi media;

    StoryHighlightService(StoryFrameRepository frames, StoryHighlightRepository highlights,
                          StoryHighlightFrameRepository highlightFrames,
                          CloseFriendRepository closeFriends, StoryViewRepository views,
                          ProfileApi profiles, MediaApi media) {
        this.frames = frames;
        this.highlights = highlights;
        this.highlightFrames = highlightFrames;
        this.closeFriends = closeFriends;
        this.views = views;
        this.profiles = profiles;
        this.media = media;
    }

    // MARK: Archive

    /** Every frame you have posted and not deleted, newest first, expiry ignored. */
    @Transactional(readOnly = true)
    List<StoryFrameDto> archive(UUID me) {
        return frames.archiveOf(me, PageRequest.of(0, MAX_ARCHIVE)).stream()
            .map(f -> StoryService.dto(f, true, null, null, null))
            .toList();
    }

    // MARK: Highlights

    @Transactional(readOnly = true)
    List<StoryHighlightDto> highlightsOf(UUID ownerId) {
        List<StoryHighlight> rows = highlights.findByOwnerIdOrderByCreatedAtDesc(ownerId);
        if (rows.isEmpty()) {
            return List.of();
        }
        Map<UUID, Integer> counts = new java.util.HashMap<>();
        for (Object[] row : highlightFrames.countsByHighlight(
                rows.stream().map(StoryHighlight::getId).toList())) {
            counts.put((UUID) row[0], ((Number) row[1]).intValue());
        }
        return rows.stream()
            .map(h -> new StoryHighlightDto(h.getId(), h.getOwnerId(), h.getTitle(),
                h.getCoverUrl(), counts.getOrDefault(h.getId(), 0), h.getCreatedAt()))
            .toList();
    }

    @Transactional(readOnly = true)
    StoryHighlightDetailDto highlight(UUID me, UUID highlightId) {
        StoryHighlight highlight = highlights.findById(highlightId).orElseThrow(
            () -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such highlight"));

        List<UUID> ordered = highlightFrames.findByHighlightIdOrderBySortOrderAsc(highlightId).stream()
            .map(StoryHighlightFrame::getFrameId)
            .toList();
        if (ordered.isEmpty()) {
            return new StoryHighlightDetailDto(highlight.getId(), highlight.getOwnerId(),
                highlight.getTitle(), highlight.getCoverUrl(), List.of());
        }
        // findLiveByIds loses the pinned order — restore it.
        Map<UUID, StoryFrame> byId = frames.findLiveByIds(ordered).stream()
            .collect(Collectors.toMap(StoryFrame::getId, f -> f));
        boolean trusted = isCloseFriendOf(highlight.getOwnerId(), me);
        Set<UUID> seen = views.viewedFrameIds(me, ordered);

        List<StoryFrameDto> playable = new ArrayList<>(ordered.size());
        for (UUID frameId : ordered) {
            StoryFrame frame = byId.get(frameId);
            if (frame == null || !visibleTo(frame, me, trusted)) {
                continue;
            }
            playable.add(StoryService.dto(frame, seen.contains(frameId), null, null, null));
        }
        return new StoryHighlightDetailDto(highlight.getId(), highlight.getOwnerId(),
            highlight.getTitle(), highlight.getCoverUrl(), playable);
    }

    @Transactional
    StoryHighlightDto create(UUID me, SaveHighlightRequest request) {
        StoryHighlight highlight = highlights.save(
            new StoryHighlight(me, request.title().trim(), blankToNull(request.coverUrl())));
        int count = pin(me, highlight.getId(), request.frameIds());
        if (highlight.getCoverUrl() != null) {
            media.markReferenced(List.of(highlight.getCoverUrl()));
        }
        return new StoryHighlightDto(highlight.getId(), me, highlight.getTitle(),
            highlight.getCoverUrl(), count, highlight.getCreatedAt());
    }

    @Transactional
    StoryHighlightDto update(UUID me, UUID highlightId, SaveHighlightRequest request) {
        StoryHighlight highlight = mine(me, highlightId);
        highlight.rename(request.title().trim(), blankToNull(request.coverUrl()));
        int count = pin(me, highlightId, request.frameIds());
        if (highlight.getCoverUrl() != null) {
            media.markReferenced(List.of(highlight.getCoverUrl()));
        }
        return new StoryHighlightDto(highlightId, me, highlight.getTitle(),
            highlight.getCoverUrl(), count, highlight.getCreatedAt());
    }

    @Transactional
    void delete(UUID me, UUID highlightId) {
        highlights.delete(mine(me, highlightId));
    }

    /** Replaces the highlight's frames wholesale, keeping the order sent. */
    private int pin(UUID me, UUID highlightId, List<UUID> frameIds) {
        highlightFrames.clearFor(highlightId);
        if (frameIds == null || frameIds.isEmpty()) {
            return 0;
        }
        // De-duplicate but keep the caller's order — it is the playback order.
        List<UUID> wanted = new ArrayList<>(new LinkedHashSet<>(frameIds));
        Map<UUID, StoryFrame> live = frames.findLiveByIds(wanted).stream()
            .collect(Collectors.toMap(StoryFrame::getId, f -> f));

        int order = 0;
        for (UUID frameId : wanted) {
            StoryFrame frame = live.get(frameId);
            if (frame == null) {
                throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such story frame: " + frameId);
            }
            if (!profiles.actsFor(me, frame.getAuthorId())) {
                throw new ResponseStatusException(HttpStatus.FORBIDDEN, "You can only highlight your own stories");
            }
            highlightFrames.save(new StoryHighlightFrame(highlightId, frameId, order++));
        }
        return order;
    }

    private StoryHighlight mine(UUID me, UUID highlightId) {
        StoryHighlight highlight = highlights.findById(highlightId).orElseThrow(
            () -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such highlight"));
        if (!profiles.actsFor(me, highlight.getOwnerId())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your highlight");
        }
        return highlight;
    }

    // MARK: Close friends

    @Transactional(readOnly = true)
    List<CloseFriendDto> closeFriendsOf(UUID me) {
        List<UUID> ids = closeFriends.findByOwnerId(me).stream().map(CloseFriend::getFriendId).toList();
        if (ids.isEmpty()) {
            return List.of();
        }
        Map<UUID, ProfileDto> people = profiles.findByIds(ids);
        return ids.stream().map(id -> {
            ProfileDto p = people.get(id);
            return new CloseFriendDto(id,
                p == null ? "Deleted user" : p.displayName() != null ? p.displayName() : p.handle(),
                p == null ? null : p.handle(),
                p == null ? null : p.avatarUrl());
        }).toList();
    }

    /** Replaces the whole list — the client edits it as a set of checkboxes. */
    @Transactional
    List<CloseFriendDto> setCloseFriends(UUID me, List<UUID> profileIds) {
        closeFriends.clearFor(me);
        if (profileIds != null) {
            for (UUID id : new LinkedHashSet<>(profileIds)) {
                if (!id.equals(me)) {
                    closeFriends.save(new CloseFriend(me, id));
                }
            }
        }
        return closeFriendsOf(me);
    }

    boolean isCloseFriendOf(UUID owner, UUID viewer) {
        return closeFriends.existsById(new CloseFriend.Key(owner, viewer));
    }

    /** A restricted frame is visible to its author and to their close friends only. */
    static boolean visibleTo(StoryFrame frame, UUID viewer, boolean isCloseFriend) {
        return frame.getAudience() != StoryAudience.CLOSE_FRIENDS
            || frame.getAuthorId().equals(viewer)
            || isCloseFriend;
    }

    private static String blankToNull(String raw) {
        return raw == null || raw.isBlank() ? null : raw.trim();
    }
}
