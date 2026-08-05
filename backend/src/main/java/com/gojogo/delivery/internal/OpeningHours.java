package com.gojogo.delivery.internal;

import org.slf4j.LoggerFactory;

import java.time.DayOfWeek;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * When a restaurant is actually open (Phase 4 M6).
 *
 * <p>Found while building M5, and it is the older of the two gaps: SPECS §9's
 * storefront {@code info} block has advertised "hours" since 2e M4 with
 * <em>nothing behind it</em>, and this vertical has never known whether a
 * kitchen was open. The `active` switch is the owner saying "we are trading" —
 * a thing somebody has to remember to flip twice a day, and therefore a thing
 * nobody flips.
 *
 * <p>The consequences were small until M5 made them not: an order placed after
 * close waits ten minutes to time out, and a <b>booking for three in the
 * morning is accepted</b> and cancelled hours later, at a moment when nobody
 * can do anything with the refund.
 *
 * <h2>Two decisions worth carrying</h2>
 *
 * <p><b>Stored as a compact string, not a table.</b> Seven days of open/close
 * is one column — {@code "MON=11:00-23:00;TUE=11:00-23:00;..."} — because it is
 * always read whole, never queried across merchants, and a seven-row child
 * table would be seven rows joined on every catalog read to answer a question
 * with one answer. A day absent means closed that day; an empty column means
 * <b>always open</b>, which is what every restaurant already in the catalog is.
 *
 * <p><b>The merchant's own timezone, and a real one.</b> Hours without a zone
 * are hours in the server's, which is UTC, which is nobody's lunchtime. A
 * restaurant that has not set one falls back to the configured platform zone
 * rather than to UTC, because the wrong local guess is closer than a definitely
 * wrong global one.
 *
 * <p>Overnight is supported and is not an edge case — a kitchen open until 2am
 * is a normal kitchen. A close before its open means it runs past midnight.
 */
record OpeningHours(List<Span> spans, ZoneId zone) {

    /** A restaurant with nothing set: open whenever it says it is trading. */
    static OpeningHours always(ZoneId zone) {
        return new OpeningHours(List.of(), zone);
    }

    boolean alwaysOpen() {
        return spans.isEmpty();
    }

    /**
     * Parses the stored form, and never throws.
     *
     * <p>A malformed schedule falls back to always-open rather than to closed,
     * which is the direction that fails safe: a bad parse that closed a
     * restaurant would take them out of the catalog with no error anywhere, and
     * they would find out from their revenue.
     *
     * <p><b>It logs, and that is not decoration.</b> The first version of this
     * failed open on every schedule ever written, because it asked
     * {@code DayOfWeek.valueOf} for {@code "WED"} and that enum spells it
     * {@code WEDNESDAY} — so every restaurant with hours was silently
     * always-open and nothing anywhere said so. The tests caught it; a
     * production instance would not have. A fallback that hides a bug needs to
     * be loud about having been taken.
     */
    static OpeningHours parse(String raw, ZoneId zone) {
        if (raw == null || raw.isBlank()) return always(zone);
        List<Span> parsed = new ArrayList<>();
        for (String part : raw.split(";")) {
            String entry = part.trim();
            if (entry.isEmpty()) continue;
            int eq = entry.indexOf('=');
            int dash = entry.indexOf('-', eq + 1);
            if (eq < 0 || dash < 0) return unreadable(raw, entry, zone);
            DayOfWeek day = day(entry.substring(0, eq).trim());
            int open = minutes(entry.substring(eq + 1, dash).trim());
            int close = minutes(entry.substring(dash + 1).trim());
            if (day == null || open < 0 || close < 0) return unreadable(raw, entry, zone);
            parsed.add(new Span(day, open, close));
        }
        return parsed.isEmpty() ? always(zone) : new OpeningHours(List.copyOf(parsed), zone);
    }

    private static OpeningHours unreadable(String raw, String entry, ZoneId zone) {
        LoggerFactory.getLogger(OpeningHours.class).warn(
            "Ignoring an unreadable opening-hours schedule (treating the restaurant as always "
                + "open): couldn't read \"{}\" in \"{}\"", entry, raw);
        return always(zone);
    }

    /**
     * A day, written the way a schedule writes it.
     *
     * <p>Both {@code MON} and {@code MONDAY} are accepted, which is the fix for
     * the bug above: the stored form is the short one because the column is a
     * string somebody may read, and {@code DayOfWeek.valueOf} only knows the
     * long one.
     */
    private static DayOfWeek day(String raw) {
        String name = raw.toUpperCase();
        for (DayOfWeek candidate : DayOfWeek.values()) {
            if (candidate.name().equals(name) || candidate.name().startsWith(name) && name.length() == 3) {
                return candidate;
            }
        }
        return null;
    }

    /** Minutes past midnight, or -1 for anything that is not {@code HH:mm}. */
    private static int minutes(String time) {
        String[] parts = time.split(":");
        if (parts.length != 2) return -1;
        try {
            int hours = Integer.parseInt(parts[0]);
            int mins = Integer.parseInt(parts[1]);
            if (hours < 0 || hours > 24 || mins < 0 || mins > 59) return -1;
            return hours * 60 + mins;
        } catch (NumberFormatException notATime) {
            return -1;
        }
    }

    /**
     * Whether the kitchen is open at that instant, in their own local time.
     *
     * <p>Checks the previous day too, which is the whole of what supports
     * overnight: 1am on Saturday is inside Friday's 18:00–02:00.
     */
    boolean openAt(OffsetDateTime instant) {
        if (alwaysOpen()) return true;
        ZonedDateTime local = instant.atZoneSameInstant(zone);
        int minuteOfDay = local.getHour() * 60 + local.getMinute();
        DayOfWeek today = local.getDayOfWeek();
        DayOfWeek yesterday = today.minus(1);
        for (Span span : spans) {
            if (span.day() == today && span.coversSameDay(minuteOfDay)) return true;
            if (span.day() == yesterday && span.coversAfterMidnight(minuteOfDay)) return true;
        }
        return false;
    }

    /**
     * One day's trading. {@code closeMinute} at or before {@code openMinute}
     * means it runs past midnight into the next day.
     */
    record Span(DayOfWeek day, int openMinute, int closeMinute) {

        boolean overnight() {
            return closeMinute <= openMinute;
        }

        boolean coversSameDay(int minuteOfDay) {
            return overnight()
                ? minuteOfDay >= openMinute
                : minuteOfDay >= openMinute && minuteOfDay < closeMinute;
        }

        /** The tail of an overnight span, read on the following day. */
        boolean coversAfterMidnight(int minuteOfDay) {
            return overnight() && minuteOfDay < closeMinute;
        }
    }
}
