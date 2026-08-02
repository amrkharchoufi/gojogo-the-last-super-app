package com.gojogo.profile;

import java.util.UUID;

/**
 * Somebody to tell when a person is in trouble.
 *
 * <p>Public because {@code travel} reads it when SOS is pressed — vertical to
 * platform, the allowed direction. It is deliberately the whole contact rather
 * than "the ids to push to": whether a contact can be reached by push or only by
 * a message the phone sends is a decision the caller has to be able to make, and
 * hiding the number here would just move that decision somewhere it has less
 * information.
 *
 * @param linkedProfileId set when this contact is also on GojoGo, which is what
 *                        turns an alarm into a push rather than a message
 *                        somebody has to send by hand. Null for most people:
 *                        the person you would call in an emergency is usually
 *                        not a user of the app you happen to be in
 */
public record EmergencyContactDto(UUID id, String name, String phone, String relationship,
                                  UUID linkedProfileId) {
}
