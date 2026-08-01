package com.gojogo.dispatch.internal;

import com.gojogo.config.ConfigApi;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/**
 * Every number in SPECS §3, read from the config registry at the point of use.
 *
 * <p>Read rather than cached in a field on purpose (the {@code ConfigApi}
 * contract says so): the registry already caches, and a knob held for the
 * lifetime of the process is a knob that needs a deploy to turn, which defeats
 * the exercise. Widening the search radius on a Friday night should be a row.
 *
 * <p>Every default here matches the row V29 seeds, so an empty config table
 * behaves identically to a populated one.
 */
@Component
class DispatchPolicy {

    private static final List<Double> DEFAULT_RADII = List.of(1.0, 3.0, 7.0);

    private final ConfigApi config;

    DispatchPolicy(ConfigApi config) {
        this.config = config;
    }

    /**
     * The rings, in order. A malformed list falls back whole rather than
     * partially: half-parsing "1,three,7" into a two-ring search is the kind of
     * quiet wrong answer this registry exists to avoid.
     */
    List<Double> waveRadiiKm() {
        String raw = config.string("dispatch.wave.radii.km", "");
        if (raw == null || raw.isBlank()) return DEFAULT_RADII;
        List<Double> parsed = new ArrayList<>();
        for (String part : raw.split(",")) {
            try {
                double km = Double.parseDouble(part.trim());
                if (km <= 0) return DEFAULT_RADII;
                parsed.add(km);
            } catch (NumberFormatException notANumber) {
                return DEFAULT_RADII;
            }
        }
        return parsed.isEmpty() ? DEFAULT_RADII : parsed;
    }

    long waveIntervalSeconds() {
        return Math.max(1, config.number("dispatch.wave.interval.seconds", 15));
    }

    int waveSize() {
        return (int) Math.clamp(config.number("dispatch.wave.size", 5), 1, 50);
    }

    long offerTtlSeconds() {
        return Math.max(5, config.number("dispatch.offer.ttl.seconds", 30));
    }

    long requestTtlSeconds() {
        return Math.max(30, config.number("dispatch.request.ttl.seconds", 300));
    }

    long positionIntervalSeconds() {
        return Math.max(1, config.number("dispatch.position.interval.seconds", 5));
    }

    long pickupLeadSeconds() {
        return Math.max(0, config.number("dispatch.pickup.lead.seconds", 420));
    }

    /** The ranking inputs, as one value object the ranker takes whole. */
    CandidateRanker.Policy ranking() {
        return new CandidateRanker.Policy(
            Math.max(5, config.number("dispatch.presence.stale.seconds", 60)),
            // Stored in hundredths so the registry holds integers everywhere.
            Math.clamp(config.number("dispatch.rating.floor.hundredths", 0), 0, 500) / 100.0,
            Math.max(1, config.number("dispatch.score.idle.full.seconds", 900)),
            Math.max(0, config.number("dispatch.score.weight.proximity", 60)),
            Math.max(0, config.number("dispatch.score.weight.rating", 25)),
            Math.max(0, config.number("dispatch.score.weight.idle", 15)));
    }
}
