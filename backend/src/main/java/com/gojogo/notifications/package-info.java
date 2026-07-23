/**
 * Notifications module — the in-app activity feed ({@code notifications}
 * schema). This is the first consumer of the social module's domain events
 * ({@code UserFollowed}, {@code PostLiked}, {@code PostCommented}): it listens
 * after the social transaction commits and persists an activity row for the
 * affected user, then serves the feed decorated with the actor's profile.
 *
 * <p>In-app first (this module); APNs fan-out is a later slice that would add a
 * push sender over these same rows. No cross-schema FKs — recipient/actor/post
 * ids are plain UUIDs resolved through public APIs.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Notifications")
package com.gojogo.notifications;
