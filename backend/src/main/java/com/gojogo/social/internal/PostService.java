package com.gojogo.social.internal;

import com.gojogo.media.MediaApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import com.gojogo.profile.ProfileKind;
import com.gojogo.social.PostCreated;
import com.gojogo.social.PostLiked;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import java.util.stream.Stream;

@Service
class PostService {

    private final PostRepository posts;
    private final PostLikeRepository likes;
    private final PostBookmarkRepository bookmarks;
    private final FollowRepository follows;
    private final ProfileApi profiles;
    private final MediaApi media;
    private final MentionService mentions;
    private final ApplicationEventPublisher events;

    PostService(PostRepository posts, PostLikeRepository likes, PostBookmarkRepository bookmarks,
                FollowRepository follows, ProfileApi profiles, MediaApi media,
                MentionService mentions, ApplicationEventPublisher events) {
        this.posts = posts;
        this.likes = likes;
        this.bookmarks = bookmarks;
        this.follows = follows;
        this.profiles = profiles;
        this.media = media;
        this.mentions = mentions;
        this.events = events;
    }

    @Transactional
    PostResponse create(UUID me, CreatePostRequest request) {
        boolean hasMedia = request.mediaItems() != null && !request.mediaItems().isEmpty();
        boolean hasText = request.text() != null && !request.text().isBlank();
        if (!hasMedia && !hasText) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Post needs text or media");
        }
        Post post = new Post(me, hasText ? request.text() : null,
            request.imageAspect() == null ? 1.0f : request.imageAspect());
        if (hasMedia) {
            for (CreateMediaItem item : request.mediaItems()) {
                post.addMedia(item.imageUrl(), item.videoUrl());
            }
            media.markReferenced(request.mediaItems().stream()
                .flatMap(item -> Stream.of(item.imageUrl(), item.videoUrl()))
                .toList());
        }
        post = posts.saveAndFlush(post);
        // The caption's @tags, resolved once here — see MentionService.
        mentions.record(MentionTarget.POST, post.getId(), me, post.getText(),
            post.getId(), null, Set.of());
        events.publishEvent(new PostCreated(post.getId(), me, post.getCreatedAt()));
        return decorate(List.of(post), me).getFirst();
    }

    // --- Feed ranking weights (see rank()) ---
    // Recency still dominates for fresh content, but a genuinely hot post
    // (lots of likes/comments) or one from someone you follow can jump the
    // visible window. Tuned so a ~12h-old post has ~37% of a brand-new one's
    // recency term, and a post with ~20 likes earns roughly one extra "fresh".
    private static final double RANK_HALF_LIFE_HOURS = 12.0;
    private static final double W_RECENCY = 1.0;
    private static final double W_ENGAGEMENT = 0.35;
    private static final double W_AFFINITY = 0.6;

    @Transactional(readOnly = true)
    FeedResponse feed(UUID me, OffsetDateTime before, int limit) {
        OffsetDateTime cursor = before == null ? OffsetDateTime.now().plusMinutes(1) : before;
        int size = Math.clamp(limit, 1, 50);
        // followed excludes me — reused for both affinity scoring and decoration
        // (decoration must not mark my own posts as "following").
        Set<UUID> followed = follows.followeeIds(me);
        List<Post> page;
        if (followed.isEmpty()) {
            // Following no one yet: recency-based discovery feed.
            page = posts.feedGlobal(cursor, PageRequest.of(0, size));
        } else {
            Set<UUID> authors = new java.util.HashSet<>(followed);
            authors.add(me);
            page = posts.feedByAuthors(authors, cursor, PageRequest.of(0, size));
        }
        // The keyset cursor stays on createdAt (stable pagination — no skips or
        // dupes across pages); ranking re-orders *within* each fetched window so
        // the next page still continues from the oldest post by time.
        OffsetDateTime nextBefore = page.size() < size ? null : page.getLast().getCreatedAt();
        List<Post> ranked = rank(page, followed);
        List<PostResponse> items = decorate(ranked, me, followed);
        return new FeedResponse(items, nextBefore);
    }

    /// Re-ranks a recency window by score = recency-decay + engagement + affinity.
    /// Pure in-memory reorder of the page — no extra queries, no post dropped.
    private List<Post> rank(List<Post> page, Set<UUID> followees) {
        if (page.size() < 2) {
            return page;
        }
        OffsetDateTime now = OffsetDateTime.now();
        return page.stream()
            .sorted(java.util.Comparator.comparingDouble((Post p) -> score(p, now, followees)).reversed())
            .toList();
    }

    private double score(Post post, OffsetDateTime now, Set<UUID> followees) {
        double ageHours = Math.max(0, java.time.Duration.between(post.getCreatedAt(), now).toMinutes()) / 60.0;
        double recency = Math.exp(-ageHours / RANK_HALF_LIFE_HOURS);
        double engagement = Math.log1p(post.getLikeCount() + 2.0 * post.getCommentCount());
        double affinity = followees.contains(post.getAuthorId()) ? 1.0 : 0.0;
        return W_RECENCY * recency + W_ENGAGEMENT * engagement + W_AFFINITY * affinity;
    }

    @Transactional(readOnly = true)
    List<PostResponse> byAuthor(UUID me, UUID authorId, int limit) {
        return decorate(posts.findByAuthorIdOrderByCreatedAtDesc(authorId,
            PageRequest.of(0, Math.clamp(limit, 1, 100))), me);
    }

    @Transactional(readOnly = true)
    PostResponse get(UUID me, UUID postId) {
        Post post = posts.findById(postId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such post"));
        return decorate(List.of(post), me).getFirst();
    }

    @Transactional
    void delete(UUID me, UUID postId) {
        Post post = posts.findById(postId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such post"));
        // `actsFor`, not `equals`: a post published as one of your business
        // profiles is still yours to delete, whichever identity you're switched to.
        if (!profiles.actsFor(me, post.getAuthorId())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your post");
        }
        posts.delete(post);
    }

    @Transactional
    void like(UUID me, UUID postId) {
        Post post = posts.findById(postId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "Post not found"));
        try {
            likes.saveAndFlush(new PostLike(postId, me));
            posts.bumpLikeCount(postId, 1);
            // Notify the author (the notifications module ignores self-likes).
            events.publishEvent(new PostLiked(postId, post.getAuthorId(), me, OffsetDateTime.now()));
        } catch (DataIntegrityViolationException alreadyLiked) {
            // idempotent — no duplicate notification
        }
    }

    @Transactional
    void unlike(UUID me, UUID postId) {
        if (likes.deleteByPostIdAndUserId(postId, me) > 0) {
            posts.bumpLikeCount(postId, -1);
        }
    }

    @Transactional
    void bookmark(UUID me, UUID postId) {
        requireExists(postId);
        try {
            bookmarks.saveAndFlush(new PostBookmark(postId, me));
        } catch (DataIntegrityViolationException alreadyBookmarked) {
            // idempotent
        }
    }

    @Transactional
    void unbookmark(UUID me, UUID postId) {
        bookmarks.deleteByPostIdAndUserId(postId, me);
    }

    List<PostResponse> decorate(List<Post> page, UUID me) {
        // feed() already has the followee set — this path (create/get/byAuthor)
        // fetches it once here.
        return decorate(page, me, follows.followeeIds(me));
    }

    List<PostResponse> decorate(List<Post> page, UUID me, Set<UUID> followed) {
        if (page.isEmpty()) {
            return List.of();
        }
        Set<UUID> postIds = page.stream().map(Post::getId).collect(Collectors.toSet());
        Set<UUID> authorIds = page.stream().map(Post::getAuthorId).collect(Collectors.toSet());
        Map<UUID, ProfileDto> authors = profiles.findByIds(authorIds);
        Set<UUID> liked = likes.likedPostIds(me, postIds);
        Set<UUID> bookmarked = bookmarks.bookmarkedPostIds(me, postIds);
        Map<UUID, List<MentionDto>> tagged = mentions.forTargets(MentionTarget.POST, postIds);
        return page.stream().map(post -> {
            ProfileDto author = authors.get(post.getAuthorId());
            return new PostResponse(
                post.getId(),
                toAuthorSummary(author, post.getAuthorId(), followed),
                post.getCreatedAt(),
                post.getText(),
                post.getImageAspect(),
                post.getMedia().stream()
                    .map(m -> new MediaItemDto(m.getId(), m.getImageUrl(), m.getVideoUrl()))
                    .toList(),
                liked.contains(post.getId()),
                bookmarked.contains(post.getId()),
                post.getLikeCount(),
                post.getCommentCount(),
                tagged.getOrDefault(post.getId(), List.of()));
        }).toList();
    }

    static AuthorSummary toAuthorSummary(ProfileDto author, UUID authorId, Set<UUID> followedByMe) {
        if (author == null) {
            return new AuthorSummary(authorId, "Deleted user", null, null, false, false, false);
        }
        String name = author.displayName() != null ? author.displayName() : author.handle();
        return new AuthorSummary(author.id(), name, author.handle(), author.avatarUrl(),
            followedByMe.contains(author.id()),
            author.kind() == ProfileKind.BUSINESS, author.verified());
    }

    private void requireExists(UUID postId) {
        if (!posts.existsById(postId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such post");
        }
    }
}
