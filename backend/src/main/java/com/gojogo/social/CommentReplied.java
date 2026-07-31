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
 */
public record CommentReplied(UUID postId, UUID parentCommentId, UUID parentAuthorId,
                             UUID replierId, UUID replyId, OffsetDateTime at) {
}
