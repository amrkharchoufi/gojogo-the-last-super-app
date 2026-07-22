package com.gojogo.social.internal;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

record AuthorSummary(UUID id, String name, String handle, String avatarUrl, boolean following) {
}

record MediaItemDto(UUID id, String imageUrl, String videoUrl) {
}

record PostResponse(UUID id, AuthorSummary author, OffsetDateTime createdAt, String text,
                    float imageAspect, List<MediaItemDto> mediaItems,
                    boolean liked, boolean bookmarked, int likeCount, int commentCount) {
}

record FeedResponse(List<PostResponse> posts, OffsetDateTime nextBefore) {
}

record CreateMediaItem(@Size(max = 500) String imageUrl, @Size(max = 500) String videoUrl) {
}

record CreatePostRequest(@Size(max = 5000) String text, Float imageAspect,
                         @Size(max = 10) List<CreateMediaItem> mediaItems) {
}

record CreateCommentRequest(@NotBlank @Size(max = 2000) String text) {
}

record CommentResponse(UUID id, AuthorSummary author, String text, boolean liked,
                       int likeCount, OffsetDateTime createdAt) {
}

record CreateStoryRequest(@NotEmpty @Size(max = 10) List<@NotBlank @Size(max = 500) String> frameImageUrls) {
}

record StoryFrameDto(UUID id, String imageUrl, boolean seen, OffsetDateTime createdAt) {
}

record StoryRingResponse(UUID authorId, String name, String handle, String avatarUrl,
                         boolean isYou, List<StoryFrameDto> frames) {
}

record ProfileViewResponse(UUID id, String name, String handle, String avatarUrl, String bio,
                           String category, long postCount, long followerCount,
                           long followingCount, boolean isOwn, boolean following) {
}
