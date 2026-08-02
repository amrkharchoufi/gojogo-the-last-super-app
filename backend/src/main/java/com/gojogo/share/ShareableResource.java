package com.gojogo.share;

import java.util.Optional;
import java.util.UUID;

/**
 * What a shared thing looks like to somebody with no account — implemented by
 * the module that owns the kind, never by this one.
 *
 * <p>The fourth of the platform-defines / vertical-implements seams
 * (ARCHITECTURE §2): {@code messaging.ConversationGuard},
 * {@code moderation.ModeratableContent}, {@code dispatch.WorkerEligibility}, and
 * this. It exists because only {@code travel} knows where a car is, and a
 * platform module reaching into a vertical to find out would invert the layering
 * that makes either of them extractable.
 *
 * <p>Rendered on <em>every</em> read rather than once at mint time. A tracking
 * link that shows a stored position is a screenshot.
 */
public interface ShareableResource {

    /** The kind this renders, matching what the vertical passed to
     *  {@link ShareApi#mint} — {@code "ride"}. */
    String kind();

    /**
     * The public view of one thing, or empty if it no longer has one.
     *
     * <p>Empty is a 404 to the viewer, and is the right answer for something
     * deleted, cancelled, or long finished. The implementation decides — this
     * module cannot know that a trip which ended an hour ago has nothing left to
     * show.
     */
    Optional<SharedView> render(UUID refId);

    /**
     * The thin payload a stranger is allowed to see. Every field here was chosen
     * by asking whether a person who found this link in a group chat should have
     * it, which is why there is no phone number, no address, no handle and no
     * profile id.
     *
     * @param headline   "Amina is driving Sara to Maarif" — first names, never
     *                   full ones
     * @param status     a sentence, already worded for a reader: this module
     *                   must not have to translate a vertical's enum
     * @param detail     the plate and the car, when there is one
     * @param latitude   where it is right now, or null when there is nothing to
     *                   show — before pickup, or after arrival
     * @param etaMinutes best guess, or null. A wrong number is worse than none
     * @param finished   true once there is nothing more to watch, so the page
     *                   can say so instead of showing a frozen dot
     */
    record SharedView(String headline, String status, String detail,
                      Double latitude, Double longitude, Integer etaMinutes,
                      String destinationLabel, boolean finished) {
    }
}
