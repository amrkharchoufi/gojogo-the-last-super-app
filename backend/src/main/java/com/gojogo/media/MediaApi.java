package com.gojogo.media;

import java.util.Collection;

/**
 * Public API of the media module. Other modules call {@link #markReferenced}
 * when they persist a media URL (post image, avatar, message attachment, …) so
 * the orphan-cleanup sweep knows the underlying S3 object is in use and must be
 * kept. URLs the media module did not mint are ignored.
 */
public interface MediaApi {

    /**
     * Marks the S3 objects behind these public URLs as referenced. Safe to call
     * with nulls, blanks, or foreign URLs — only keys this module minted match.
     */
    void markReferenced(Collection<String> urls);
}
