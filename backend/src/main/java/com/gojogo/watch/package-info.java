/**
 * Watch module — user video, long-form and shorts ({@code watch} schema). A
 * vertical product surface (ARCHITECTURE.md §2): it owns its catalog and its
 * engagement (likes, saves, views, comments) and calls platform APIs for
 * everything else.
 *
 * <p>It reads {@link com.gojogo.profile.ProfileApi} to decorate a video with
 * its channel, {@link com.gojogo.social.SocialGraphApi} for the follow graph —
 * <em>subscribers are followers</em>, there is no second graph — and
 * {@link com.gojogo.media.MediaApi} to keep an uploaded thumbnail or movie from
 * being swept as an orphan.
 *
 * <p>Playback is still the direct-S3 object a post's video already uses. The
 * transcode pipeline (S3 → MediaConvert → HLS) is Phase 3 and slots in behind
 * {@code video_url} without touching this module's surface.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Watch")
package com.gojogo.watch;
