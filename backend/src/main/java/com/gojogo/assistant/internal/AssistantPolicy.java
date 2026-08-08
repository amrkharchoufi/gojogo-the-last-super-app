package com.gojogo.assistant.internal;

import com.gojogo.config.ConfigApi;
import org.springframework.stereotype.Component;

/**
 * MADELEINE.md's <b>CONFIG</b> knobs, read from the config registry rather than
 * from {@code application.yml}.
 *
 * <p>Deliberate: these are policy, and this codebase's convention is that a
 * policy number is a row somebody can change on a bad Friday, not a deploy
 * (SPECS §14 — the same reason dispatch keeps its search radii there and only
 * its poll interval in the yaml). The spec's own values are the defaults, so an
 * empty registry behaves exactly as written.
 *
 * <p>Read at the point of use, never cached in a field: the registry already
 * caches, and a knob held for the lifetime of the process is a knob that needs
 * a deploy, which defeats the exercise.
 */
@Component
class AssistantPolicy {

    private final ConfigApi config;

    AssistantPolicy(ConfigApi config) {
        this.config = config;
    }

    /** §4: the loop stops here however well it is going. */
    int maxToolCallsPerTurn() {
        return (int) clamp(config.number("assistant.turn.max.tool.calls", 16), 1, 64);
    }

    /** §4: wall-clock ceiling on a turn. Exhausting it ends the turn honestly. */
    int turnDeadlineSeconds() {
        return (int) clamp(config.number("assistant.turn.deadline.seconds", 120), 5, 600);
    }

    /** §4: list results are capped at this many items before entering context. */
    int toolResultMaxItems() {
        return (int) clamp(config.number("assistant.tool.result.max.items", 8), 1, 50);
    }

    /**
     * How long a trimmed result may be before the sidekick is asked to summarise
     * it (§4: "the sidekick summarizes anything bigger; raw JSON never enters the
     * brain's context"). Not in the spec as a number — the spec says "bigger"
     * and this is where bigger gets defined.
     */
    int toolResultMaxChars() {
        return (int) clamp(config.number("assistant.tool.result.max.chars", 1200), 200, 20000);
    }

    /** §4: how much of the thread is replayed into context each turn. */
    int contextTailMessages() {
        return (int) clamp(config.number("assistant.context.tail.messages", 24), 2, 200);
    }

    /** §4 rate limit. Counted from the ledger, so it holds across instances. */
    int turnsPerUserPerHour() {
        return (int) clamp(config.number("assistant.turns.per.user.per.hour", 30), 1, 10000);
    }

    /** §5: how long a confirm card stays live. */
    int actionTtlMinutes() {
        return (int) clamp(config.number("assistant.action.ttl.minutes", 10), 1, 1440);
    }

    /** Whether the sidekick names conversations. Off costs a blank title, which
     *  the list screen already draws a placeholder for. */
    boolean titlesEnabled() {
        return config.flag("assistant.titles.enabled", true);
    }

    private static long clamp(long value, long min, long max) {
        return Math.clamp(value, min, max);
    }
}
