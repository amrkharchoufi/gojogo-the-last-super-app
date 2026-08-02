package com.gojogo.travel.internal;

import com.gojogo.config.ConfigApi;
import org.springframework.stereotype.Component;

/**
 * Every knob SPECS §2 names, read from the config registry at the point of use.
 *
 * <p>The price list itself is a table ({@link PricingConfig}) because it is
 * per-category and effective-dated; what lives here is the policy <em>around</em>
 * a fare — how long a price stands, how many times people may haggle, what
 * changing your mind costs. Read rather than cached in a field, per the
 * {@code ConfigApi} contract: a knob held for the life of the process needs a
 * deploy to turn, which is the thing the registry exists to avoid.
 */
@Component
class TravelPolicy {

    private final ConfigApi config;

    TravelPolicy(ConfigApi config) {
        this.config = config;
    }

    /**
     * Counters allowed in total — the driver's, and the rider's answer to it.
     * Haggling is a feature; an auction is not.
     */
    int maxRounds() {
        return (int) Math.clamp(config.number("travel.negotiation.max.rounds", 2), 1, 8);
    }

    /** Longer than a dispatch offer, deliberately: being sent a job is a yes/no,
     *  and being sent a price is a decision. */
    long offerTtlSeconds() {
        return Math.max(10, config.number("travel.offer.ttl.seconds", 45));
    }

    long requestTtlSeconds() {
        return Math.max(30, config.number("travel.request.ttl.seconds", 300));
    }

    long cancelFeeMinor() {
        return Math.max(0, config.number("travel.cancel.fee.minor", 200));
    }

    long ratingWindowDays() {
        return Math.max(1, config.number("travel.rating.window.days", 7));
    }

    long roadFactorBps() {
        return Math.clamp(config.number("travel.route.road.factor.bps", 13_000), 10_000, 30_000);
    }

    long speedKmh() {
        return Math.clamp(config.number("travel.route.speed.kmh", 24), 5, 120);
    }

    /**
     * How far above the suggestion an offer may go before it is treated as a
     * typo. Protects the <em>rider</em>: 5000 where 50 was meant is a mistake the
     * server should catch, not a windfall.
     */
    long maxOfferMultipleBps() {
        return Math.max(10_000, config.number("travel.offer.max.multiple.bps", 30_000));
    }

    // MARK: Safety (Phase 3 M5, SPECS §10)

    /** The floor on a share link's life. A trip's own estimate usually beats it;
     *  this is what stops a two-minute hop producing a link that has expired by
     *  the time the message is read. */
    long shareTtlMinutes() {
        return Math.clamp(config.number("safety.share.ttl.minutes", 180), 5, 24 * 60);
    }

    /** How long a link keeps working after the trip ends. Deliberately generous:
     *  a link that dies at the kerb dies at the one moment somebody is looking
     *  at it. */
    long shareGraceMinutes() {
        return Math.clamp(config.number("safety.share.grace.minutes", 60), 0, 24 * 60);
    }

    /**
     * The number the SOS screen dials.
     *
     * <p>112 by default because it works across the EU and on most GSM networks
     * worldwide, which is the right answer when we do not know where somebody
     * is. A market overrides it with {@code safety.emergency.number.<REGION>}.
     *
     * <p>The <em>server</em> never dials it. Placing an emergency call on
     * somebody's behalf would be a claim about integration with emergency
     * services this system has no right to make (SPECS §10).
     */
    String emergencyNumber() {
        return config.string("safety.emergency.number", "112");
    }
}
