/**
 * Media module — presigned S3 upload/delivery plus orphan-upload tracking and
 * cleanup ({@code media} schema). Other modules call {@link com.gojogo.media.MediaApi}
 * to mark an uploaded object as referenced so the daily sweep keeps it.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Media")
package com.gojogo.media;
