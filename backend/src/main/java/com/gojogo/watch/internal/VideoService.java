package com.gojogo.watch.internal;

import com.gojogo.media.MediaApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import com.gojogo.profile.ProfileKind;
import com.gojogo.social.SocialGraphApi;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.Arrays;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/** Publishing, the two feeds, engagement, and owner-only edit/delete. */
@Service
class VideoService {

    private static final int MAX_PAGE = 50;

    private final VideoRepository videos;
    private final VideoLikeRepository likes;
    private final VideoSaveRepository saves;
    private final VideoViewRepository views;
    private final ProfileApi profiles;
    private final SocialGraphApi graph;
    private final MediaApi media;

    VideoService(VideoRepository videos, VideoLikeRepository likes, VideoSaveRepository saves,
                 VideoViewRepository views, ProfileApi profiles, SocialGraphApi graph,
                 MediaApi media) {
        this.videos = videos;
        this.likes = likes;
        this.saves = saves;
        this.views = views;
        this.profiles = profiles;
        this.graph = graph;
        this.media = media;
    }

    // MARK: Publishing

    @Transactional
    VideoResponse create(UUID me, CreateVideoRequest request) {
        if (request.videoUrl() == null || request.videoUrl().isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "A video needs a file");
        }
        VideoKind kind = VideoKind.parse(request.kind());
        String title = request.title() == null ? "" : request.title().trim();
        if (title.isEmpty()) {
            // Never invent a title with the channel name or a date in it — an
            // untitled upload says so, and the owner can fix it from Edit.
            title = kind == VideoKind.SHORT ? "Untitled short" : "Untitled video";
        }
        Video video = videos.save(new Video(me, kind, title,
            request.description() == null ? "" : request.description().trim(),
            blankToNull(request.thumbUrl()), request.videoUrl(),
            request.durationSeconds() == null ? 0 : request.durationSeconds()));
        media.markReferenced(Arrays.asList(request.thumbUrl(), request.videoUrl()));
        return decorate(List.of(video), me).getFirst();
    }

    @Transactional
    VideoResponse update(UUID me, UUID videoId, UpdateVideoRequest request) {
        Video video = requireOwned(me, videoId);
        video.edit(request.title(), request.description(), blankToNull(request.thumbUrl()));
        media.markReferenced(List.of(request.thumbUrl() == null ? "" : request.thumbUrl()));
        return decorate(List.of(videos.save(video)), me).getFirst();
    }

    @Transactional
    void delete(UUID me, UUID videoId) {
        // Likes, saves, views and comments cascade with the row (V18) — a
        // dangling like on a deleted video would keep a count alive forever.
        videos.delete(requireOwned(me, videoId));
    }

    // MARK: Feeds

    @Transactional(readOnly = true)
    VideoFeedResponse feed(UUID me, String kindRaw, int limit, OffsetDateTime before) {
        VideoKind kind = VideoKind.parse(kindRaw);
        int size = Math.clamp(limit, 1, MAX_PAGE);
        OffsetDateTime cursor = before == null ? OffsetDateTime.now().plusMinutes(1) : before;
        List<Video> page = videos.feed(kind, cursor, notVisibleTo(me), me, PageRequest.of(0, size));
        // Keyset cursor stays on createdAt so pages never skip or repeat.
        OffsetDateTime nextBefore = page.size() < size ? null : page.getLast().getCreatedAt();
        return new VideoFeedResponse(decorate(page, me), nextBefore);
    }

    @Transactional(readOnly = true)
    List<VideoResponse> byAuthor(UUID me, UUID authorId, String kindRaw, int limit) {
        // Empty rather than forbidden, same as a blocked person's post grid.
        if (graph.blockedBetween(me, authorId)) {
            return List.of();
        }
        var page = PageRequest.of(0, Math.clamp(limit, 1, 100));
        List<Video> rows = kindRaw == null || kindRaw.isBlank()
            ? videos.byAuthor(authorId, me, page)
            : videos.byAuthor(authorId, VideoKind.parse(kindRaw), me, page);
        return decorate(rows, me);
    }

    @Transactional(readOnly = true)
    List<VideoResponse> saved(UUID me, int limit) {
        return decorate(videos.savedBy(me, PageRequest.of(0, Math.clamp(limit, 1, 100))), me);
    }

    @Transactional(readOnly = true)
    VideoResponse get(UUID me, UUID videoId) {
        return decorate(List.of(requireVisible(me, videoId)), me).getFirst();
    }

    // MARK: Engagement

    @Transactional
    void like(UUID me, UUID videoId) {
        requireVisible(me, videoId);
        try {
            likes.saveAndFlush(new VideoLike(videoId, me));
            videos.bumpLikeCount(videoId, 1);
        } catch (DataIntegrityViolationException alreadyLiked) {
            // idempotent — a retry must not double the count
        }
    }

    @Transactional
    void unlike(UUID me, UUID videoId) {
        if (likes.deleteByVideoIdAndUserId(videoId, me) > 0) {
            videos.bumpLikeCount(videoId, -1);
        }
    }

    @Transactional
    void save(UUID me, UUID videoId) {
        requireVisible(me, videoId);
        try {
            saves.saveAndFlush(new VideoSave(videoId, me));
        } catch (DataIntegrityViolationException alreadySaved) {
            // idempotent
        }
    }

    @Transactional
    void unsave(UUID me, UUID videoId) {
        saves.deleteByVideoIdAndUserId(videoId, me);
    }

    /**
     * Counts this user as a viewer. First open per person counts; every open
     * after that is a no-op, which is why the client may call it freely on
     * every playback without inflating anything.
     */
    @Transactional
    void recordView(UUID me, UUID videoId) {
        requireVisible(me, videoId);
        // existsById first: an @IdClass entity merges rather than inserts, so a
        // duplicate-key catch would never fire here (see the assigned-id note
        // in PROGRESS.md).
        if (views.existsById(new VideoView.Key(videoId, me))) {
            return;
        }
        try {
            views.saveAndFlush(new VideoView(videoId, me));
            videos.bumpViewCount(videoId);
        } catch (DataIntegrityViolationException raced) {
            // Two devices at once — the row is there either way, count once.
        }
    }

    // MARK: Decoration

    List<VideoResponse> decorate(List<Video> page, UUID me) {
        if (page.isEmpty()) {
            return List.of();
        }
        Set<UUID> videoIds = page.stream().map(Video::getId).collect(Collectors.toSet());
        Set<UUID> authorIds = page.stream().map(Video::getAuthorId).collect(Collectors.toSet());
        Map<UUID, ProfileDto> authors = profiles.findByIds(authorIds);
        Map<UUID, Long> followers = graph.followerCounts(authorIds);
        Set<UUID> followed = graph.followeeIds(me);
        Set<UUID> liked = likes.likedVideoIds(me, videoIds);
        Set<UUID> savedIds = saves.savedVideoIds(me, videoIds);
        return page.stream().map(v -> new VideoResponse(
            v.getId(),
            v.getKind().name(),
            channel(authors.get(v.getAuthorId()), v.getAuthorId(), followers, followed),
            v.getTitle(),
            v.getDescription(),
            v.getThumbUrl(),
            v.getVideoUrl(),
            v.getDurationSeconds(),
            liked.contains(v.getId()),
            savedIds.contains(v.getId()),
            v.getLikeCount(),
            v.getCommentCount(),
            v.getViewCount(),
            v.getCreatedAt())).toList();
    }

    /** Shared with {@link VideoCommentService} so a commenter renders the same way. */
    VideoChannel channel(ProfileDto profile, UUID profileId,
                         Map<UUID, Long> followerCounts, Set<UUID> followedByMe) {
        if (profile == null) {
            return new VideoChannel(profileId, "Deleted user", null, null, 0, false, false, false);
        }
        String name = profile.displayName() != null ? profile.displayName() : profile.handle();
        return new VideoChannel(profile.id(), name, profile.handle(), profile.avatarUrl(),
            followerCounts.getOrDefault(profile.id(), 0L),
            followedByMe.contains(profile.id()),
            profile.kind() == ProfileKind.BUSINESS, profile.verified());
    }

    Map<UUID, Long> followerCounts(Collection<UUID> ids) {
        return graph.followerCounts(ids);
    }

    Set<UUID> followeeIds(UUID me) {
        return graph.followeeIds(me);
    }

    Video require(UUID videoId) {
        return videos.findById(videoId).orElseThrow(
            () -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such video"));
    }

    private Video requireOwned(UUID me, UUID videoId) {
        Video video = require(videoId);
        if (!profiles.actsFor(me, video.getAuthorId())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your video");
        }
        return video;
    }

    /**
     * The video, if this viewer is allowed to know it exists. 404 with the same
     * wording as a video that never existed for both a block and a moderator's
     * hide: "you may not see this" still confirms there is a this.
     */
    Video requireVisible(UUID me, UUID videoId) {
        Video video = require(videoId);
        if (graph.blockedBetween(me, video.getAuthorId())
            || (video.isHidden() && !video.getAuthorId().equals(me))) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such video");
        }
        return video;
    }

    /** Everyone a block stands between, padded so JPQL's {@code not in} always
     *  has something to compare against. */
    private Collection<UUID> notVisibleTo(UUID me) {
        Set<UUID> hidden = new java.util.HashSet<>(graph.blockedIds(me));
        hidden.add(NOBODY);
        return hidden;
    }

    /** The id nobody has — see {@link #notVisibleTo}. */
    private static final UUID NOBODY = new UUID(0L, 0L);

    /** Moderation's takedown (2e M5) — see {@code ModeratableContent}. */
    @Transactional
    void setHidden(UUID videoId, boolean hidden) {
        videos.findById(videoId).ifPresent(v -> {
            v.setHidden(hidden);
            videos.save(v);
        });
    }

    @Transactional
    void removeAsModerator(UUID videoId) {
        videos.findById(videoId).ifPresent(videos::delete);
    }

    @Transactional(readOnly = true)
    java.util.Optional<Video> find(UUID videoId) {
        return videos.findById(videoId);
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }
}
