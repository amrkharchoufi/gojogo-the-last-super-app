package com.gojogo.media;

import java.util.UUID;

/**
 * Uploads that must <em>not</em> be public.
 *
 * <p>Everything {@code /v1/media/presign} mints lands under {@code media/*},
 * which the bucket policy makes world-readable (an interim measure until the
 * account is verified for CloudFront — see PROGRESS.md). That is right for a
 * post photo and catastrophic for an ID card, so KYC papers get their own
 * prefix, no public URL at all, and a short-lived presigned GET when a reviewer
 * actually needs to look at one.
 *
 * <p>The object key is the only handle a caller keeps. It is not a URL, it is
 * not guessable from one, and it grants nothing on its own.
 */
public interface MediaDocumentApi {

    /**
     * A presigned PUT into the private area.
     *
     * @param ownerId who is uploading — part of the key, so an object is
     *                traceable back to a person without a database read
     * @param folder  a short slug for what this belongs to (e.g. "partner"),
     *                so private objects are separable by purpose
     */
    DocumentUpload presignDocumentUpload(UUID ownerId, String folder, String contentType);

    /**
     * A short-lived URL that reads one private object. Minted per view and
     * never stored: a link that has expired is a link that cannot leak.
     */
    String presignDocumentRead(String objectKey);

    /** Deletes a private object. Called when its owning row goes away — the
     *  orphan sweep only knows about the public {@code media/*} prefix. */
    void deleteDocument(String objectKey);

    /**
     * @param objectKey      what the caller stores; never a public URL
     * @param expiresSeconds how long the PUT stays valid
     */
    record DocumentUpload(String uploadUrl, String objectKey, String contentType,
                          long expiresSeconds) {
    }
}
