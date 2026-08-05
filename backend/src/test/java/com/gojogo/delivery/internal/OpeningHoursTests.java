package com.gojogo.delivery.internal;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * When a restaurant is open (Phase 4 M6).
 *
 * <p>The two cases worth writing tests for are the two that would otherwise be
 * discovered by a customer: <b>overnight</b>, because a kitchen open until 2am
 * is an ordinary kitchen and a naive same-day comparison closes it at midnight;
 * and <b>timezone</b>, because hours with no zone are hours in the server's,
 * the server's is UTC, and a Casablanca kitchen would close at four in the
 * afternoon.
 */
class OpeningHoursTests {

    private static final ZoneId CASA = ZoneId.of("Africa/Casablanca");

    @Test
    @DisplayName("no schedule is always open, which is every restaurant before this")
    void blankIsAlwaysOpen() {
        OpeningHours hours = OpeningHours.parse("", CASA);

        assertThat(hours.alwaysOpen()).isTrue();
        assertThat(hours.openAt(at(2026, 8, 5, 3, 0))).isTrue();
    }

    @Test
    void insideTheDaysSpanIsOpenAndOutsideItIsNot() {
        OpeningHours hours = OpeningHours.parse("WED=11:00-23:00", CASA);

        assertThat(hours.openAt(at(2026, 8, 5, 12, 0))).isTrue();
        assertThat(hours.openAt(at(2026, 8, 5, 10, 59))).isFalse();
        assertThat(hours.openAt(at(2026, 8, 5, 23, 0))).isFalse();
    }

    @Test
    @DisplayName("a day that isn't listed is closed")
    void anAbsentDayIsClosed() {
        OpeningHours hours = OpeningHours.parse("WED=11:00-23:00", CASA);

        // Thursday.
        assertThat(hours.openAt(at(2026, 8, 6, 12, 0))).isFalse();
    }

    /** A kitchen open until 2am is a normal kitchen, and 1am on Thursday is
     *  inside Wednesday's span. */
    @Test
    @DisplayName("an overnight span runs past midnight into the next day")
    void overnightSpansWork() {
        OpeningHours hours = OpeningHours.parse("WED=18:00-02:00", CASA);

        assertThat(hours.openAt(at(2026, 8, 5, 20, 0))).isTrue();   // Wed evening
        assertThat(hours.openAt(at(2026, 8, 6, 1, 0))).isTrue();    // Thu 1am
        assertThat(hours.openAt(at(2026, 8, 6, 2, 0))).isFalse();   // Thu 2am, shut
        assertThat(hours.openAt(at(2026, 8, 5, 17, 59))).isFalse(); // Wed, not yet
    }

    /**
     * The whole reason the zone is stored. Midday in Casablanca is 11:00 UTC,
     * and a schedule read in the server's zone would put a lunchtime order
     * outside a lunchtime opening.
     */
    @Test
    @DisplayName("hours are read in the restaurant's timezone, not the server's")
    void theZoneIsTheRestaurants() {
        OpeningHours casa = OpeningHours.parse("WED=11:00-23:00", CASA);
        OpeningHours tokyo = OpeningHours.parse("WED=11:00-23:00", ZoneId.of("Asia/Tokyo"));

        // 10:30 UTC on a Wednesday: 11:30 in Casablanca (open), 19:30 in Tokyo
        // (also open) — and 03:30 Thursday in Tokyo would not be.
        OffsetDateTime instant = OffsetDateTime.parse("2026-08-05T10:30:00Z");
        assertThat(casa.openAt(instant)).isTrue();
        assertThat(tokyo.openAt(instant)).isTrue();
        assertThat(tokyo.openAt(OffsetDateTime.parse("2026-08-05T18:30:00Z"))).isFalse();
    }

    /**
     * A bad parse falls back to always-open rather than to closed, and the
     * direction is the point: closing a restaurant silently would take them out
     * of the catalog with no error anywhere, and they would find out from their
     * revenue.
     */
    @Test
    @DisplayName("a malformed schedule fails open, not closed")
    void rubbishFailsOpen() {
        assertThat(OpeningHours.parse("nonsense", CASA).alwaysOpen()).isTrue();
        assertThat(OpeningHours.parse("MON=25:00-26:00", CASA).alwaysOpen()).isTrue();
        assertThat(OpeningHours.parse("FUNDAY=11:00-23:00", CASA).alwaysOpen()).isTrue();
        assertThat(OpeningHours.parse("MON=1100-2300", CASA).alwaysOpen()).isTrue();
    }

    @Test
    void severalDaysParseAndAreIndependent() {
        OpeningHours hours = OpeningHours.parse("WED=11:00-15:00;THU=18:00-23:00", CASA);

        assertThat(hours.openAt(at(2026, 8, 5, 12, 0))).isTrue();
        assertThat(hours.openAt(at(2026, 8, 5, 19, 0))).isFalse();
        assertThat(hours.openAt(at(2026, 8, 6, 19, 0))).isTrue();
        assertThat(hours.openAt(at(2026, 8, 6, 12, 0))).isFalse();
    }

    /** Local wall-clock time in Casablanca, which is how a person there would
     *  say it. */
    private static OffsetDateTime at(int year, int month, int day, int hour, int minute) {
        return ZonedDateTime.of(year, month, day, hour, minute, 0, 0, CASA).toOffsetDateTime();
    }
}
