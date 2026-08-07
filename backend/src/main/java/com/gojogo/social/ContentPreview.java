package com.gojogo.social;

import java.util.UUID;

/**
 * Enough of a post, a story frame or a comment to render a row about it
 * somewhere else — a thumbnail and a line of text, nothing more.
 *
 * <p>This exists because "someone liked your post" is not an answer to the
 * question the person actually has, which is <em>which</em> post. The activity
 * feed shows the thumbnail next to the row for exactly that reason, and it
 * cannot reach into the social module's tables to get one.
 *
 * <p>{@code thumbnailUrl} is null for anything without a picture — a text-only
 * post, a text story card, a comment — and {@code text} is null when there is
 * nothing to quote. A preview with both null is still worth returning: it says
 * the thing exists, which is what a tap needs to know.
 */
public record ContentPreview(UUID id, String thumbnailUrl, String text) {
}
