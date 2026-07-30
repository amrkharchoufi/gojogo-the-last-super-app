package com.gojogo.watch.internal;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/**
 * The channel behind a video.
 *
 * @param subscriberCount the author's follower count — subscribers <em>are</em>
 *                        followers, resolved server-side so the client never
 *                        has to invent or guess one
 * @param subscribed      whether you follow them; the Subscribe button's state
 */
record VideoChannel(UUID id, String name, String handle, String avatarUrl,
                    long subscriberCount, boolean subscribed,
                    boolean business, boolean verified) {
}

/**
 * A video as the client renders it. Everything displayed is either authored by
 * the uploader or counted here — there are no derived-looking fields the server
 * made up.
 *
 * @param durationSeconds whole seconds; the client formats "1:00" from it
 * @param viewCount       distinct viewers, not playbacks (see V18__watch.sql)
 */
record VideoResponse(UUID id, String kind, VideoChannel channel, String title,
                     String description, String thumbUrl, String videoUrl,
                     int durationSeconds, boolean liked, boolean saved,
                     int likeCount, int commentCount, int viewCount,
                     OffsetDateTime createdAt) {
}

record VideoFeedResponse(List<VideoResponse> videos, OffsetDateTime nextBefore) {
}

/**
 * Publishing a video. {@code title} carries a short's caption too — a short has
 * no separate body, so it simply leaves {@code description} empty.
 */
record CreateVideoRequest(@Size(max = 16) String kind,
                          @Size(max = 300) String title,
                          @Size(max = 5000) String description,
                          @Size(max = 500) String thumbUrl,
                          @NotBlank @Size(max = 500) String videoUrl,
                          @PositiveOrZero Integer durationSeconds,
                          UUID actAsProfileId) {
}

/** Editing a published video. A null field is "leave it", not "clear it". */
record UpdateVideoRequest(@Size(max = 300) String title,
                          @Size(max = 5000) String description,
                          @Size(max = 500) String thumbUrl) {
}

record VideoCommentResponse(UUID id, VideoChannel author, String text, boolean liked,
                            int likeCount, OffsetDateTime createdAt) {
}

record CreateVideoCommentRequest(@NotBlank @Size(max = 2000) String text, UUID actAsProfileId) {
}
