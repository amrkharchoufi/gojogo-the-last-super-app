/**
 * Music module — the shared track catalog ({@code music} schema). A platform
 * capability (ARCHITECTURE.md §2), not a story feature: stories are its first
 * consumer, shorts and posts are the obvious next ones.
 *
 * <p>Other modules use {@link com.gojogo.music.MusicApi} to resolve a track and
 * to record that one was used. They never read the table, and they never hold a
 * foreign key to it — a consumer stores its own snapshot of the track so a
 * pulled or edited catalog row can't break content that already shipped.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Music")
package com.gojogo.music;
