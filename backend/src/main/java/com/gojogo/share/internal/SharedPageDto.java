package com.gojogo.share.internal;

import java.time.OffsetDateTime;

/**
 * What the public endpoint returns to somebody with no account.
 *
 * <p>Every field here survived the question "should a person who found this link
 * in a group chat have it?" — which is why there is no handle, no profile id, no
 * phone number and no full name. It is enough to see that somebody is safe and
 * where they have got to, and nothing more.
 *
 * @param sos true when the link was raised as an alarm rather than shared for
 *            convenience. The page says so, because a person opening an SOS link
 *            needs to know it is one before they read anything else
 */
record SharedPageDto(String kind, String headline, String status, String detail,
                     Double latitude, Double longitude, Integer etaMinutes,
                     String destinationLabel, boolean finished, boolean sos,
                     OffsetDateTime expiresAt) {
}
