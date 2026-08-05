package com.gojogo.services.internal;

import com.gojogo.config.ConfigApi;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Bookable slots = weekly template − exception dates − live bookings − CONFIG
 * buffer, inside the CONFIG horizon (SPECS §7). Computed on demand and never
 * stored: a calendar row that mirrors the template is a calendar row that
 * disagrees with it by Thursday.
 *
 * <p>All wall-clock arithmetic happens in the provider's own zone; what leaves
 * this class is instants.
 */
@Service
class AvailabilityService {

    private final AvailabilityRuleRepository rules;
    private final AvailabilityExceptionRepository exceptions;
    private final BookingRepository bookings;
    private final ConfigApi config;

    AvailabilityService(AvailabilityRuleRepository rules,
                        AvailabilityExceptionRepository exceptions,
                        BookingRepository bookings, ConfigApi config) {
        this.rules = rules;
        this.exceptions = exceptions;
        this.bookings = bookings;
        this.config = config;
    }

    int horizonDays() {
        return (int) Math.clamp(config.number("services.booking.horizon.days", 60), 1, 365);
    }

    private int bufferMinutes() {
        return (int) Math.clamp(config.number("services.booking.buffer.minutes", 15), 0, 240);
    }

    /**
     * The offerable start times for one service over {@code days} from
     * {@code from}, stepping through each template window on the service's own
     * duration plus the buffer.
     */
    @Transactional(readOnly = true)
    List<OffsetDateTime> slots(Provider provider, ServiceOffering service,
                               LocalDate from, int days) {
        ZoneId zone = provider.zone();
        LocalDate first = from == null ? LocalDate.now(zone) : from;
        LocalDate horizon = LocalDate.now(zone).plusDays(horizonDays());
        LocalDate last = first.plusDays(Math.clamp(days, 1, 31) - 1);
        if (last.isAfter(horizon)) last = horizon;

        List<AvailabilityRule> template =
            rules.findByProviderIdOrderByDayOfWeekAscStartMinuteAsc(provider.getId());
        if (template.isEmpty()) return List.of();
        Set<LocalDate> closed = exceptions
            .findByProviderIdAndOnDateBetween(provider.getId(), first, last).stream()
            .map(AvailabilityException::getOnDate)
            .collect(Collectors.toSet());

        OffsetDateTime windowStart = first.atStartOfDay(zone).toOffsetDateTime();
        OffsetDateTime windowEnd = last.plusDays(1).atStartOfDay(zone).toOffsetDateTime();
        List<Booking> live = bookings.liveInWindow(provider.getId(),
            windowStart.minusMinutes(1440 + bufferMinutes()), windowEnd);

        int step = service.getDurationMinutes() + bufferMinutes();
        OffsetDateTime now = OffsetDateTime.now();
        List<OffsetDateTime> result = new ArrayList<>();
        for (LocalDate day = first; !day.isAfter(last); day = day.plusDays(1)) {
            if (closed.contains(day)) continue;
            int weekday = day.getDayOfWeek().getValue();
            for (AvailabilityRule rule : template) {
                if (rule.getDayOfWeek() != weekday) continue;
                for (int minute = rule.getStartMinute();
                     minute + service.getDurationMinutes() <= rule.getEndMinute();
                     minute += step) {
                    ZonedDateTime local = day.atStartOfDay(zone).plusMinutes(minute);
                    OffsetDateTime start = local.toOffsetDateTime();
                    if (!start.isAfter(now)) continue;
                    OffsetDateTime end = start.plusMinutes(service.getDurationMinutes()
                        + bufferMinutes());
                    boolean taken = live.stream().anyMatch(b ->
                        b.overlaps(start.minusMinutes(bufferMinutes()), end));
                    if (!taken) result.add(start);
                }
            }
        }
        return result;
    }

    /** The gate a booking request passes: inside the horizon, on the template,
     *  not on a closed day, and clear of every live booking plus buffer. */
    @Transactional(readOnly = true)
    void requireFree(Provider provider, ServiceOffering service, OffsetDateTime startsAt) {
        ZoneId zone = provider.zone();
        OffsetDateTime now = OffsetDateTime.now();
        if (!startsAt.isAfter(now)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "That time has already passed");
        }
        if (startsAt.isAfter(now.plusDays(horizonDays()))) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Bookings open at most " + horizonDays() + " days ahead");
        }
        ZonedDateTime local = startsAt.atZoneSameInstant(zone);
        LocalDate day = local.toLocalDate();
        if (!exceptions.findByProviderIdAndOnDateBetween(provider.getId(), day, day).isEmpty()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "The provider is closed that day");
        }
        int minute = local.getHour() * 60 + local.getMinute();
        int endMinute = minute + service.getDurationMinutes();
        boolean inTemplate = rules
            .findByProviderIdOrderByDayOfWeekAscStartMinuteAsc(provider.getId()).stream()
            .anyMatch(r -> r.getDayOfWeek() == local.getDayOfWeek().getValue()
                && r.getStartMinute() <= minute && endMinute <= r.getEndMinute());
        if (!inTemplate) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That time is outside the provider's hours");
        }
        int buffer = bufferMinutes();
        OffsetDateTime blockFrom = startsAt.minusMinutes(buffer);
        OffsetDateTime blockTo = startsAt.plusMinutes(service.getDurationMinutes() + buffer);
        boolean taken = bookings.liveInWindow(provider.getId(),
                blockFrom.minusMinutes(1440), blockTo).stream()
            .anyMatch(b -> b.overlaps(blockFrom, blockTo));
        if (taken) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That slot was just taken");
        }
    }

    // MARK: Template CRUD

    @Transactional
    List<ServiceDtos.AvailabilityRuleResponse> replaceRules(
        Provider provider, List<ServiceDtos.AvailabilityRuleRequest> requested) {
        for (ServiceDtos.AvailabilityRuleRequest rule : requested) {
            if (rule.endMinute() <= rule.startMinute()) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A window must end after it starts");
            }
        }
        rules.deleteByProviderId(provider.getId());
        return requested.stream()
            .map(r -> rules.save(new AvailabilityRule(provider.getId(), r.dayOfWeek(),
                r.startMinute(), r.endMinute())))
            .map(r -> new ServiceDtos.AvailabilityRuleResponse(r.getId(), r.getDayOfWeek(),
                r.getStartMinute(), r.getEndMinute()))
            .toList();
    }

    @Transactional(readOnly = true)
    List<ServiceDtos.AvailabilityRuleResponse> rulesFor(Provider provider) {
        return rules.findByProviderIdOrderByDayOfWeekAscStartMinuteAsc(provider.getId()).stream()
            .map(r -> new ServiceDtos.AvailabilityRuleResponse(r.getId(), r.getDayOfWeek(),
                r.getStartMinute(), r.getEndMinute()))
            .toList();
    }

    @Transactional
    void addException(Provider provider, LocalDate onDate) {
        boolean exists = !exceptions
            .findByProviderIdAndOnDateBetween(provider.getId(), onDate, onDate).isEmpty();
        if (!exists) {
            exceptions.save(new AvailabilityException(provider.getId(), onDate));
        }
    }

    @Transactional
    void removeException(Provider provider, LocalDate onDate) {
        exceptions.deleteByProviderIdAndOnDate(provider.getId(), onDate);
    }

    @Transactional(readOnly = true)
    List<LocalDate> exceptionsFor(Provider provider) {
        return exceptions.findByProviderIdOrderByOnDateAsc(provider.getId()).stream()
            .map(AvailabilityException::getOnDate)
            .toList();
    }
}
