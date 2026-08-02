package com.gojogo.delivery.internal;

import java.time.Duration;
import java.time.OffsetDateTime;

/**
 * The countdown, and the pin on the map.
 *
 * <p>All that survives of {@code DeliveryTimeline}, which held the four
 * durations a simulated fulfilment ran on and answered two very different
 * questions with them: <em>where is this order</em> and <em>what should the
 * customer's screen say</em>. Real couriers answer the first, so only the second
 * is left — and it is now read off timestamps that people caused rather than
 * computed from {@code placedAt} and a set of constants.
 */
final class Eta {

    private Eta() {
    }

    /** Minutes left on the promise, floored at 1 while the order is still live —
     *  "0 min" on a countdown reads as "it's here", and it isn't. */
    static int minutesLeft(CustomerOrder order) {
        if (order.getStatus().isTerminal()) {
            return 0;
        }
        long seconds = Duration.between(OffsetDateTime.now(), order.getEtaAt()).getSeconds();
        return (int) Math.max(1, Math.ceilDiv(seconds, 60));
    }

    /**
     * How far along the last leg the courier is, 0–1, for the moving pin.
     *
     * <p>Measured rather than simulated: it is the courier's actual reported
     * position projected onto the straight line from the restaurant to the door.
     * Under the old timeline this was elapsed-time-over-total, which drew a pin
     * that moved smoothly whatever the courier was doing — including standing
     * still. Falls back to 0 when any of the three positions is unknown, which
     * is honest: a pin that has not moved is better than one that is guessing.
     *
     * <p>Straight-line, like every other distance in this system until dispatch
     * grows a routing authority (SPECS §3). A courier who goes round a one-way
     * system shows as slightly behind, which is the right direction to be wrong
     * in.
     */
    static double courierProgress(CustomerOrder order, Double courierLat, Double courierLon,
                                  Double fromLat, Double fromLon) {
        if (order.getStatus() == OrderStatus.DELIVERED) {
            return 1;
        }
        if (order.getStatus() != OrderStatus.DELIVERING
            || courierLat == null || courierLon == null || fromLat == null || fromLon == null
            || order.getAddressLatitude() == null || order.getAddressLongitude() == null) {
            return 0;
        }
        double whole = distance(fromLat, fromLon,
            order.getAddressLatitude(), order.getAddressLongitude());
        if (whole <= 0) {
            return 0;
        }
        double left = distance(courierLat, courierLon,
            order.getAddressLatitude(), order.getAddressLongitude());
        return Math.clamp(1 - (left / whole), 0d, 1d);
    }

    /** Great-circle metres. Duplicated from {@code dispatch}'s own geometry on
     *  purpose — two lines of trigonometry are not worth a public API, and a
     *  shared one would be a platform module handing out a maths helper. */
    private static double distance(double lat1, double lon1, double lat2, double lon2) {
        double earthRadiusMetres = 6_371_000;
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
            + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
            * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        return 2 * earthRadiusMetres * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }
}
