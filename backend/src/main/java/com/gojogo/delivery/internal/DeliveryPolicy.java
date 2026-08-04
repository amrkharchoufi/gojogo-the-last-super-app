package com.gojogo.delivery.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.dispatch.VehicleCategory;
import org.springframework.stereotype.Component;

import java.util.EnumSet;
import java.util.Set;

/**
 * The numbers a real fulfilment runs on, read from the config registry at the
 * point of use.
 *
 * <p>This is what is left of {@code DeliveryTimeline}, and the difference is the
 * whole milestone. The timeline held four durations that <em>decided</em> where
 * an order was: twenty seconds to cook, seventy-five to reach the restaurant.
 * Nothing here decides anything. A kitchen says when it will be ready and a
 * courier says when they have it; these are the estimate shown to a customer
 * before either of them has spoken, and the lead time that says how early to go
 * looking.
 *
 * <p>Read rather than cached in a field, per the {@code ConfigApi} contract: a
 * knob held for the lifetime of the process is a knob that needs a deploy to
 * turn. Every default matches the row {@code V35} seeds, so an empty config
 * table behaves exactly like a populated one.
 */
@Component
class DeliveryPolicy {

    private static final Set<VehicleCategory> DEFAULT_CATEGORIES =
        EnumSet.of(VehicleCategory.BIKE, VehicleCategory.SCOOTER, VehicleCategory.CAR);

    private final ConfigApi config;

    DeliveryPolicy(ConfigApi config) {
        this.config = config;
    }

    /**
     * How long before the food is ready to start looking (SPECS §3's
     * "approaching readiness" trigger). Too early and a courier stands at a
     * counter unpaid; too late and the food does.
     */
    long pickupLeadSeconds() {
        return Math.max(0, config.number("delivery.courier.pickup.lead.seconds", 420));
    }

    /** Used when a restaurant accepts without saying how long they need. */
    int defaultPrepMinutes() {
        return (int) Math.clamp(config.number("delivery.prep.default.minutes", 20), 1, maxPrepMinutes());
    }

    /** A typo of 200 for 20 holds somebody's money for three hours. */
    int maxPrepMinutes() {
        return (int) Math.clamp(config.number("delivery.prep.max.minutes", 180), 1, 1440);
    }

    /** How long an order waits on a restaurant that never answers. */
    long acceptTimeoutMinutes() {
        return Math.max(1, config.number("delivery.merchant.accept.timeout.minutes", 10));
    }

    /**
     * Most merchants one order may span (Phase 4 M3, SPECS §5). One courier
     * collects every bag — the per-leg multi-courier split is not built — and
     * this cap is what keeps that honest: three counters is a trip one person
     * makes, five is a relay.
     */
    int maxMerchantsPerOrder() {
        return (int) Math.clamp(config.number("delivery.order.max.merchants", 3), 1, 10);
    }

    /**
     * Ready-to-door, for the customer's countdown. A flat number until dispatch
     * has a routing authority — SPECS §3 reserves Mapbox Directions for that and
     * it is not built, and a made-up per-order estimate would be no more honest
     * than a made-up flat one, only harder to reason about.
     */
    long dropoffMinutes() {
        return Math.max(1, config.number("delivery.dropoff.minutes", 15));
    }

    // MARK: Handoff integrity (Phase 4 M2)

    /**
     * How a delivery is handed over when the customer expresses no preference.
     * PIN rather than CONFIRM because a default should be the option that proves
     * something, and rather than PHOTO because most people are at the door.
     */
    HandoffMode defaultHandoffMode() {
        return HandoffMode.parse(config.string("delivery.handoff.mode.default", ""),
            HandoffMode.PIN);
    }

    /**
     * Wrong delivery PINs before the photo fallback opens.
     *
     * <p>Floored at 1, because a zero here would open the fallback before the
     * courier had typed anything — a knob that turns a check off is a knob
     * somebody will eventually turn by accident, and this one would do it
     * silently.
     */
    int handoffMaxAttempts() {
        return (int) Math.clamp(config.number("delivery.handoff.max.attempts", 3), 1, 10);
    }

    /** Digits in the pickup code and the delivery PIN. */
    int handoffCodeLength() {
        return (int) Math.clamp(config.number("delivery.handoff.code.length", 6), 4, 8);
    }

    /**
     * Which vehicles may be offered a delivery. A set rather than one value: a
     * basket that fits on a bike also fits in a car, and a city with no bikes
     * out on a Tuesday should still get its dinner. An unparseable or empty list
     * falls back whole — a half-parsed set would narrow the search silently,
     * which is the failure mode this registry exists to avoid.
     */
    Set<VehicleCategory> courierCategories() {
        String raw = config.string("delivery.courier.categories", "");
        if (raw == null || raw.isBlank()) return DEFAULT_CATEGORIES;
        Set<VehicleCategory> parsed = EnumSet.noneOf(VehicleCategory.class);
        for (String part : raw.split(",")) {
            try {
                parsed.add(VehicleCategory.valueOf(part.trim().toUpperCase()));
            } catch (IllegalArgumentException notACategory) {
                return DEFAULT_CATEGORIES;
            }
        }
        return parsed.isEmpty() ? DEFAULT_CATEGORIES : parsed;
    }
}
