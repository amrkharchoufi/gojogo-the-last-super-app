package com.gojogo.social.internal;

import com.gojogo.storefront.StorefrontDocument;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/** @param business a business profile — the app draws the badge from this, not from the category text */
record AuthorSummary(UUID id, String name, String handle, String avatarUrl, boolean following,
                     boolean business, boolean verified) {
}

record MediaItemDto(UUID id, String imageUrl, String videoUrl) {
}

/**
 * Someone tagged in a body of text.
 *
 * @param handle the handle <em>as it was written</em> — the token the client
 *               finds in the text to underline. It is not necessarily this
 *               person's handle today; {@code profileId} is what the tap follows.
 */
record MentionDto(UUID profileId, String handle) {
}

record PostResponse(UUID id, AuthorSummary author, OffsetDateTime createdAt, String text,
                    float imageAspect, List<MediaItemDto> mediaItems,
                    boolean liked, boolean bookmarked, int likeCount, int commentCount,
                    List<MentionDto> mentions) {
}

record FeedResponse(List<PostResponse> posts, OffsetDateTime nextBefore) {
}

record CreateMediaItem(@Size(max = 500) String imageUrl, @Size(max = 500) String videoUrl) {
}

record CreatePostRequest(@Size(max = 5000) String text, Float imageAspect,
                         @Size(max = 10) List<CreateMediaItem> mediaItems,
                         UUID actAsProfileId) {
}

/** @param parentId the comment being answered; null posts a new top-level comment */
record CreateCommentRequest(@NotBlank @Size(max = 2000) String text, UUID parentId,
                            UUID actAsProfileId) {
}

/**
 * @param parentId null on a top-level comment
 * @param replies  the answers under it — always empty on a reply itself, since
 *                 threads are one level deep
 * @param replyCount the true total, which is what the "view N replies" control
 *                 reads; {@code replies} may be a first page of that
 */
record CommentResponse(UUID id, AuthorSummary author, String text, boolean liked,
                       int likeCount, OffsetDateTime createdAt, UUID parentId,
                       int replyCount, List<MentionDto> mentions,
                       List<CommentResponse> replies) {
}

/**
 * One frame to post. Everything past {@code mediaType} is optional — a text
 * card carries only a caption and a background, a photo only an image URL.
 */
record CreateStoryFrame(@Size(max = 16) String mediaType,
                        @Size(max = 500) String imageUrl,
                        @Size(max = 500) String videoUrl,
                        Integer durationMs,
                        @Size(max = 2000) String caption,
                        @Size(max = 8000) String overlays,
                        @Size(max = 32) String background,
                        @Size(max = 16) String audience,
                        /* Sound: the catalog track plus the clip window. The client
                         * sends only the id and the window — every displayed field is
                         * resolved server-side, so it can't be spoofed. */
                        UUID musicTrackId,
                        Integer musicStartMs,
                        Integer musicDurationMs) {
}

/** The sound on a frame, as the client renders and plays it. */
record StoryMusicDto(UUID trackId, String title, String artist, String artworkUrl,
                     String audioUrl, int startMs, int durationMs) {
}

/**
 * {@code frames} is the current shape. {@code frameImageUrls} is the original
 * image-only body, still accepted so an app build from before V11 keeps
 * posting through a rolling deploy; it maps to one IMAGE frame per URL.
 */
record CreateStoryRequest(@Valid @Size(max = 10) List<CreateStoryFrame> frames,
                          @Size(max = 10) List<@NotBlank @Size(max = 500) String> frameImageUrls,
                          UUID actAsProfileId) {

    boolean isEmpty() {
        return (frames == null || frames.isEmpty())
            && (frameImageUrls == null || frameImageUrls.isEmpty());
    }
}

/**
 * @param viewerCount how many people have seen it, and {@code replyCount} how
 *                    many replied — both are the author's own analytics, so
 *                    they are null on everyone else's frames
 * @param myReaction  the emoji <em>you</em> left on it, if any
 */
record StoryFrameDto(UUID id, String mediaType, String imageUrl, String videoUrl,
                     Integer durationMs, String caption, String overlays, String background,
                     String audience, boolean seen, OffsetDateTime createdAt,
                     OffsetDateTime expiresAt, Integer viewerCount, Integer replyCount,
                     String myReaction, StoryMusicDto music) {
}

record StoryRingResponse(UUID authorId, String name, String handle, String avatarUrl,
                         boolean isYou, boolean muted, List<StoryFrameDto> frames) {
}

record StoryReactionRequest(@NotBlank @Size(max = 16) String emoji) {
}

record StoryReplyRequest(@NotBlank @Size(max = 1000) String text) {
}

/** @param mine whether you sent it — the author's list mixes senders */
record StoryCommentDto(UUID id, UUID frameId, UUID authorId, String authorName,
                       String authorHandle, String authorAvatarUrl, String text,
                       OffsetDateTime createdAt, boolean mine) {
}

record StoryViewerDto(UUID id, String name, String handle, String avatarUrl,
                      String reaction, OffsetDateTime viewedAt) {
}

record StoryHighlightDto(UUID id, UUID ownerId, String title, String coverUrl,
                         int frameCount, OffsetDateTime createdAt) {
}

/** A highlight opened for playback — the same frames the story viewer renders. */
record StoryHighlightDetailDto(UUID id, UUID ownerId, String title, String coverUrl,
                               List<StoryFrameDto> frames) {
}

record SaveHighlightRequest(@NotBlank @Size(max = 60) String title,
                            @Size(max = 500) String coverUrl,
                            @Size(max = 100) List<UUID> frameIds,
                            UUID actAsProfileId) {
}

record CloseFriendsRequest(@Size(max = 500) List<UUID> profileIds, UUID actAsProfileId) {
}

record CloseFriendDto(UUID id, String name, String handle, String avatarUrl) {
}

/**
 * @param kind     PERSON or BUSINESS
 * @param isOwner  the viewer owns this business profile — what turns the
 *                 profile screen into the owner's own
 * @param business the business-only block; null for a person
 * @param home     the blocks a business arranged on its own page (SPECS §9);
 *                 always present, and empty (version 0) for a person and for a
 *                 business that has never arranged one
 */
record ProfileViewResponse(UUID id, String name, String handle, String avatarUrl, String bio,
                           String category, long postCount, long followerCount,
                           long followingCount, boolean isOwn, boolean following,
                           String kind, boolean verified, boolean isOwner,
                           BusinessBlock business, StorefrontDocument home) {
}

record BusinessBlock(UUID ownerProfileId, String contactPhone, String contactEmail,
                     String websiteUrl, String addressLine, String city, String country,
                     Double latitude, Double longitude, String openingHours) {
}
