package com.gojogo.messaging;

/**
 * A vertical's reference card stamped onto a conversation — an opaque, labeled
 * pointer back to whatever started the thread (a listing today; a delivery order
 * or a ride later). The messaging module stores and echoes it without
 * interpreting it: {@code kind}/{@code refId} let the client (and, later,
 * payments) resolve the real object, and {@code title}/{@code subtitle}/
 * {@code imageUrl} are the pre-rendered card so no cross-module read is needed to
 * draw it.
 *
 * <p>Kept deliberately generic — the same shape a {@code delivery} or
 * {@code travel} thread would carry — so the messaging module never gains a
 * dependency on any vertical. See {@link MessagingApi}.
 *
 * @param kind     the vertical's type tag, e.g. {@code "listing"}
 * @param refId    the referenced object's id (a UUID string for a listing)
 * @param title    card headline (the listing title)
 * @param subtitle secondary line (a price label, or {@code "On ask"})
 * @param imageUrl a thumbnail URL, or {@code null}
 */
public record ConversationContext(
    String kind,
    String refId,
    String title,
    String subtitle,
    String imageUrl) {
}
