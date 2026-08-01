package com.gojogo.social;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Domain event published when a comment is answered. Consumed by the
 * notifications module to tell the author of the comment being replied to.
 *
 * <p>Deliberately separate from {@link PostCommented}: a reply is addressed to
 * the person above you in the thread, not to whoever owns the post, and sending
 * both would make every busy thread notify the post's author dozens of times.
 *
 * @param parentCommentId the comment actually answered — <b>not</b> the thread
 *                        root it gets filed under. Replies are flattened to one
 *                        level for rendering, but answering someone's reply is
 *                        addressed to them, not to whoever opened the thread.
 */
public record CommentReplied(UUID postId, UUID parentCommentId, UUID parentAuthorId,
                             UUID replierId, UUID replyId, OffsetDateTime at) {
}
