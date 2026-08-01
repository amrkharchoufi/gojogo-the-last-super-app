package com.gojogo.social.internal;

import com.gojogo.media.MediaApi;
import com.gojogo.music.MusicApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
class StoryService {

    /** Instagram caps a story's sound at 15s; so does this. */
    private static final int MAX_CLIP_MS = 15_000;

    private final StoryFrameRepository frames;
    private final StoryViewRepository views;
    private final StoryReactionRepository reactions;
    private final StoryCommentRepository comments;
    private final StoryMuteRepository mutes;
    private final CloseFriendRepository closeFriends;
    private final FollowRepository follows;
    private final ProfileApi profiles;
    private final MediaApi media;
    private final MusicApi music;

    StoryService(StoryFrameRepository frames, StoryViewRepository views,
                 StoryReactionRepository reactions, StoryCommentRepository comments,
                 StoryMuteRepository mutes, CloseFriendRepository closeFriends,
                 FollowRepository follows, ProfileApi profiles, MediaApi media,
                 MusicApi music) {
        this.music = music;
        this.frames = frames;
        this.views = views;
        this.reactions = reactions;
        this.comments = comments;
        this.mutes = mutes;
        this.closeFriends = closeFriends;
        this.follows = follows;
        this.profiles = profiles;
        this.media = media;
    }

    @Transactional
    List<StoryFrameDto> create(UUID me, CreateStoryRequest request) {
        if (request.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "A story needs at least one frame");
        }
        List<CreateStoryFrame> specs = request.frames() != null && !request.frames().isEmpty()
            ? request.frames()
            : request.frameImageUrls().stream()
                .map(url -> new CreateStoryFrame("IMAGE", url, null, null, null, null, null, null,
                    null, null, null))
                .toList();

        List<StoryFrameDto> created = new ArrayList<>(specs.size());
        List<String> uploaded = new ArrayList<>();
        for (CreateStoryFrame spec : specs) {
            StoryFrame frame = frames.save(toFrame(me, spec));
            uploaded.addAll(frame.mediaUrls());
            created.add(dto(frame, false, 0, 0, null));
        }
        // Tells the media module these uploads are in use, so the orphan sweep
        // leaves them alone.
        media.markReferenced(uploaded);
        return created;
    }

    private StoryFrame toFrame(UUID me, CreateStoryFrame spec) {
        StoryMediaType type = StoryMediaType.parse(spec.mediaType());
        String image = blankToNull(spec.imageUrl());
        String video = blankToNull(spec.videoUrl());
        String caption = blankToNull(spec.caption());

        // Mirror the V11 CHECK here so a malformed body is a 400, not a 500 out
        // of the database.
        switch (type) {
            case IMAGE -> require(image != null, "An image story needs imageUrl");
            case VIDEO -> require(video != null, "A video story needs videoUrl");
            case TEXT -> require(caption != null, "A text story needs a caption");
        }
        if (type == StoryMediaType.TEXT) {
            // A text card carries no media even if a client sent some.
            image = null;
            video = null;
        }
        Integer duration = spec.durationMs() == null
            ? null
            : Math.max(500, Math.min(60_000, spec.durationMs()));

        StoryFrame frame = new StoryFrame(me, type, image, video, duration, caption,
            blankToNull(spec.overlays()), blankToNull(spec.background()),
            StoryAudience.parse(spec.audience()));
        attachMusic(frame, spec);
        return frame;
    }

    /**
     * Resolves the chosen track and copies it onto the frame. The client sends
     * an id and a clip window and nothing else — title, artist, artwork and the
     * audio URL are all read from the catalog here, so a client can't post a
     * frame claiming to be a song it isn't.
     */
    private void attachMusic(StoryFrame frame, CreateStoryFrame spec) {
        if (spec.musicTrackId() == null) {
            return;
        }
        var track = music.find(spec.musicTrackId()).orElseThrow(
            () -> new ResponseStatusException(HttpStatus.BAD_REQUEST, "No such track"));

        int start = Math.max(0, spec.musicStartMs() == null ? 0 : spec.musicStartMs());
        // A clip can't start past the end of the track, or run off it.
        start = Math.min(start, Math.max(0, track.durationMs() - 1_000));
        int requested = spec.musicDurationMs() == null ? MAX_CLIP_MS : spec.musicDurationMs();
        int clip = Math.max(1_000, Math.min(Math.min(requested, MAX_CLIP_MS),
            track.durationMs() - start));

        frame.attach(new StoryMusic(track.id(), track.title(), track.artist(),
            track.artworkUrl(), track.audioUrl(), start, clip));
        music.recordUse(track.id());
    }

    /**
     * Story rings for the home rail: your own ring first, then the people you
     * follow — rings with something unseen ahead of fully-seen ones, each group
     * most-recently-posted first, and anyone you muted last. Within a ring,
     * frames run oldest to newest, which is the order the viewer plays them in.
     *
     * <p>A muted person is sorted to the back and flagged rather than dropped:
     * mute means "stop putting this in front of me", not "make it unreachable".
     */
    @Transactional(readOnly = true)
    List<StoryRingResponse> rings(UUID me) {
        Set<UUID> authorIds = new HashSet<>(follows.followeeIds(me));
        authorIds.add(me);
        // Whose close-friends lists am I on? Everything else restricted drops out.
        Set<UUID> trustedBy = closeFriends.ownersWhoTrust(me);
        List<StoryFrame> active = frames.liveByAuthors(authorIds, OffsetDateTime.now(), me).stream()
            .filter(f -> StoryHighlightService.visibleTo(f, me, trustedBy.contains(f.getAuthorId())))
            .toList();
        if (active.isEmpty()) {
            return List.of();
        }
        Set<UUID> frameIds = active.stream().map(StoryFrame::getId).collect(Collectors.toSet());
        Set<UUID> seen = views.viewedFrameIds(me, frameIds);
        Set<UUID> muted = mutes.mutedIds(me);
        Map<UUID, Integer> viewerCounts = viewerCounts(frameIds);
        Map<UUID, Integer> replyCounts = replyCounts(frameIds);
        Map<UUID, String> myReactions = myReactions(me, frameIds);

        Map<UUID, List<StoryFrame>> byAuthor = active.stream()
            .collect(Collectors.groupingBy(StoryFrame::getAuthorId, LinkedHashMap::new, Collectors.toList()));
        Map<UUID, ProfileDto> authors = profiles.findByIds(byAuthor.keySet());

        List<StoryRingResponse> rings = new ArrayList<>();
        byAuthor.forEach((authorId, authorFrames) -> {
            boolean isYou = authorId.equals(me);
            ProfileDto author = authors.get(authorId);
            String name = author == null ? "Deleted user"
                : author.displayName() != null ? author.displayName() : author.handle();
            rings.add(new StoryRingResponse(
                authorId,
                name,
                author == null ? null : author.handle(),
                author == null ? null : author.avatarUrl(),
                isYou,
                muted.contains(authorId),
                authorFrames.stream()
                    // Viewer and reply counts are the author's own analytics —
                    // never another viewer's business.
                    .map(f -> dto(f, seen.contains(f.getId()),
                        isYou ? viewerCounts.getOrDefault(f.getId(), 0) : null,
                        isYou ? replyCounts.getOrDefault(f.getId(), 0) : null,
                        myReactions.get(f.getId())))
                    .toList()));
        });
        rings.sort(ringOrder());
        return rings;
    }

    /** You · unmuted · unseen (newest first) · seen (newest first) · muted. */
    private static Comparator<StoryRingResponse> ringOrder() {
        return Comparator
            .comparing((StoryRingResponse r) -> !r.isYou())
            .thenComparing(StoryRingResponse::muted)
            .thenComparing(r -> r.frames().stream().allMatch(StoryFrameDto::seen))
            .thenComparing(StoryService::lastPostedAt, Comparator.reverseOrder());
    }

    private static OffsetDateTime lastPostedAt(StoryRingResponse ring) {
        return ring.frames().stream()
            .map(StoryFrameDto::createdAt)
            .max(Comparator.naturalOrder())
            .orElse(OffsetDateTime.MIN);
    }

    /** Moderation's takedown (2e M5) — see {@code ModeratableContent}. A story
     *  expires on its own in 24 hours, so a hide here mostly matters for the
     *  archive and any highlight it was pinned into. */
    @Transactional
    void setHidden(UUID frameId, boolean hidden) {
        frames.findById(frameId).ifPresent(frame -> {
            frame.setHidden(hidden);
            frames.save(frame);
        });
    }

    /** Soft, like the author's own delete: a story's viewers and replies are
     *  somebody's record of a conversation, and the frame is unreachable either
     *  way. */
    @Transactional
    void removeAsModerator(UUID frameId) {
        frames.findById(frameId).ifPresent(frame -> {
            frame.softDelete();
            frames.save(frame);
        });
    }

    @Transactional(readOnly = true)
    java.util.Optional<StoryFrame> findFrame(UUID frameId) {
        return frames.findById(frameId).filter(f -> f.getDeletedAt() == null);
    }

    private Map<UUID, Integer> viewerCounts(Set<UUID> frameIds) {
        return tally(views.countsByFrame(frameIds));
    }

    private Map<UUID, Integer> replyCounts(Set<UUID> frameIds) {
        return tally(comments.countsByFrame(frameIds));
    }

    private Map<UUID, String> myReactions(UUID me, Set<UUID> frameIds) {
        Map<UUID, String> mine = new HashMap<>();
        for (StoryReaction r : reactions.mineOn(me, frameIds)) {
            mine.put(r.getFrameId(), r.getEmoji());
        }
        return mine;
    }

    /** {@code [frameId, count]} rows from a group-by into a lookup. */
    private static Map<UUID, Integer> tally(List<Object[]> rows) {
        Map<UUID, Integer> counts = new HashMap<>();
        for (Object[] row : rows) {
            counts.put((UUID) row[0], ((Number) row[1]).intValue());
        }
        return counts;
    }

    @Transactional
    void markSeen(UUID me, UUID frameId) {
        StoryFrame frame = liveFrame(frameId);
        if (frame.getAuthorId().equals(me)) {
            // Looking at your own story isn't a view.
            return;
        }
        StoryView.Key key = new StoryView.Key(frameId, me);
        // Assigned-id entity: save() would merge and rewrite viewedAt, quietly
        // moving an old view to the top of the author's list.
        if (!views.existsById(key)) {
            views.save(new StoryView(frameId, me));
        }
    }

    @Transactional
    void delete(UUID me, UUID frameId) {
        StoryFrame frame = liveFrame(frameId);
        if (!profiles.actsFor(me, frame.getAuthorId())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your story");
        }
        frame.softDelete();
    }

    StoryFrame liveFrame(UUID frameId) {
        return frames.findById(frameId)
            .filter(f -> f.getDeletedAt() == null)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such story frame"));
    }

    static StoryFrameDto dto(StoryFrame frame, boolean seen, Integer viewerCount,
                             Integer replyCount, String myReaction) {
        return new StoryFrameDto(
            frame.getId(),
            frame.getMediaType().name(),
            frame.getImageUrl(),
            frame.getVideoUrl(),
            frame.getDurationMs(),
            frame.getCaption(),
            frame.getOverlaysJson(),
            frame.getBackground(),
            frame.getAudience().name(),
            seen,
            frame.getCreatedAt(),
            frame.getExpiresAt(),
            viewerCount,
            replyCount,
            myReaction,
            musicDto(frame.getMusic()));
    }

    private static StoryMusicDto musicDto(StoryMusic music) {
        if (music == null) {
            return null;
        }
        return new StoryMusicDto(music.getTrackId(), music.getTitle(), music.getArtist(),
            music.getArtworkUrl(), music.getAudioUrl(),
            music.getStartMs(), music.getDurationMs());
    }

    private static void require(boolean ok, String message) {
        if (!ok) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, message);
        }
    }

    private static String blankToNull(String raw) {
        return raw == null || raw.isBlank() ? null : raw.trim();
    }
}
