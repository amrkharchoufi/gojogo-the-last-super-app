package com.gojogo.social.internal;

import com.gojogo.media.MediaApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
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
    private final ApplicationEventPublisher events;

    PostService(PostRepository posts, PostLikeRepository likes, PostBookmarkRepository bookmarks,
                FollowRepository follows, ProfileApi profiles, MediaApi media,
                ApplicationEventPublisher events) {
        this.posts = posts;
        this.likes = likes;
        this.bookmarks = bookmarks;
        this.follows = follows;
        this.profiles = profiles;
        this.media = media;
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
        post = posts.save(post);
        events.publishEvent(new PostCreated(post.getId(), me, post.getCreatedAt()));
        return decorate(List.of(post), me).getFirst();
    }

    @Transactional(readOnly = true)
    FeedResponse feed(UUID me, OffsetDateTime before, int limit) {
        OffsetDateTime cursor = before == null ? OffsetDateTime.now().plusMinutes(1) : before;
        int size = Math.clamp(limit, 1, 50);
        Set<UUID> followees = new java.util.HashSet<>(follows.followeeIds(me));
        List<Post> page;
        if (followees.isEmpty()) {
            // Following no one yet: recency-based discovery feed.
            page = posts.feedGlobal(cursor, PageRequest.of(0, size));
        } else {
            followees.add(me);
            page = posts.feedByAuthors(followees, cursor, PageRequest.of(0, size));
        }
        List<PostResponse> items = decorate(page, me);
        OffsetDateTime nextBefore = page.size() < size ? null : page.getLast().getCreatedAt();
        return new FeedResponse(items, nextBefore);
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
        if (!post.getAuthorId().equals(me)) {
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
        if (page.isEmpty()) {
            return List.of();
        }
        Set<UUID> postIds = page.stream().map(Post::getId).collect(Collectors.toSet());
        Set<UUID> authorIds = page.stream().map(Post::getAuthorId).collect(Collectors.toSet());
        Map<UUID, ProfileDto> authors = profiles.findByIds(authorIds);
        Set<UUID> liked = likes.likedPostIds(me, postIds);
        Set<UUID> bookmarked = bookmarks.bookmarkedPostIds(me, postIds);
        Set<UUID> followed = follows.followeeIds(me);
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
                post.getCommentCount());
        }).toList();
    }

    static AuthorSummary toAuthorSummary(ProfileDto author, UUID authorId, Set<UUID> followedByMe) {
        if (author == null) {
            return new AuthorSummary(authorId, "Deleted user", null, null, false);
        }
        String name = author.displayName() != null ? author.displayName() : author.handle();
        return new AuthorSummary(author.id(), name, author.handle(), author.avatarUrl(),
            followedByMe.contains(author.id()));
    }

    private void requireExists(UUID postId) {
        if (!posts.existsById(postId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such post");
        }
    }
}
