package com.gojogo.services.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.messaging.ConversationContext;
import com.gojogo.messaging.MessagingApi;
import com.gojogo.services.BookingConfirmed;
import com.gojogo.services.BookingRequested;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * The booking state machine (SPECS §7), and every rule that moves it.
 *
 * <p>The shape of the money follows who decided what. A priced service holds
 * at request, and the provider's confirm is just a yes. A quoted service holds
 * at quote-acceptance — and that acceptance <em>is</em> the confirmation,
 * because the provider already said yes by naming a number. Declines and
 * timeouts release in full; a customer cancelling a confirmed booking pays the
 * CONFIG tier; a provider cancelling pays nothing to nobody — their calendar,
 * their problem, never the customer's.
 */
@Service
class BookingService {

    private final BookingRepository bookings;
    private final ServiceOfferingRepository offerings;
    private final ProviderDirectory directory;
    private final AvailabilityService availability;
    private final BookingPayments payments;
    private final MessagingApi messaging;
    private final ConfigApi config;
    private final ApplicationEventPublisher events;

    BookingService(BookingRepository bookings, ServiceOfferingRepository offerings,
                   ProviderDirectory directory, AvailabilityService availability,
                   BookingPayments payments, MessagingApi messaging, ConfigApi config,
                   ApplicationEventPublisher events) {
        this.bookings = bookings;
        this.offerings = offerings;
        this.directory = directory;
        this.availability = availability;
        this.payments = payments;
        this.messaging = messaging;
        this.config = config;
        this.events = events;
    }

    // MARK: Customer verbs

    @Transactional
    ServiceDtos.BookingResponse request(UUID me, ServiceDtos.BookingRequestBody body) {
        ServiceOffering service = offerings.findById(body.serviceId())
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such service"));
        Provider provider = directory.require(service.getProviderId());
        if (!service.isBrowsable() || provider.isSuspended()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such service");
        }
        if (provider.getOwnerUserId().equals(me)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "That's your own service");
        }
        availability.requireFree(provider, service, body.startsAt());

        Booking booking = new Booking(service.getId(), provider.getId(), me,
            body.startsAt(), service.getDurationMinutes(), service.getPriceCents(), body.note());
        Booking saved = bookings.save(booking);
        // Payment held at request (SPECS §7) — a quoted service holds later,
        // when the number exists.
        payments.hold(saved, service.getName());
        // The thread every booking gets, stamped with the booking card.
        UUID conversation = messaging.openDirectConversation(me, provider.getOwnerUserId(),
            bookingContext(saved, service));
        saved.conversation(conversation);
        events.publishEvent(new BookingRequested(saved.getId(), provider.getOwnerUserId(),
            service.getName(), saved.getStartsAt()));
        return toResponse(saved, service, provider);
    }

    /** Accepting a quote holds the money and confirms in one act — the
     *  provider already said yes by naming the number. */
    @Transactional
    ServiceDtos.BookingResponse acceptQuote(UUID me, UUID bookingId) {
        Booking booking = requireCustomer(me, bookingId);
        requireStatus(booking, BookingStatus.REQUESTED);
        if (booking.getQuotedAt() == null || booking.getPriceCents() == null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "No quote to accept yet — ask in the thread");
        }
        if (booking.getPaymentStatus() == BookingPaymentState.HELD) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Already accepted");
        }
        ServiceOffering service = serviceOf(booking);
        payments.hold(booking, service.getName());
        booking.confirmed(OffsetDateTime.now());
        Provider provider = directory.require(booking.getProviderId());
        events.publishEvent(new BookingConfirmed(booking.getId(), booking.getCustomerId(),
            service.getName(), booking.getStartsAt()));
        return toResponse(bookings.save(booking), service, provider);
    }

    /**
     * The customer backs out. A REQUESTED booking is free. A CONFIRMED one
     * pays the CONFIG tier: free until {@code services.booking.cancel.free.hours}
     * before the start, then {@code services.booking.cancel.fee.bps} of the
     * price.
     */
    @Transactional
    ServiceDtos.BookingResponse cancelAsCustomer(UUID me, UUID bookingId) {
        Booking booking = requireCustomer(me, bookingId);
        if (booking.getStatus() != BookingStatus.REQUESTED
            && booking.getStatus() != BookingStatus.CONFIRMED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "The booking is " + booking.getStatus() + " — nothing to cancel");
        }
        Provider provider = directory.require(booking.getProviderId());
        ServiceOffering service = serviceOf(booking);
        long fee = cancellationFeeIfCancelledNow(booking);
        if (fee > 0) {
            payments.settleCancellationFee(booking, provider.getId(),
                provider.getDisplayName(), fee);
        } else {
            payments.release(booking, "Booking cancelled");
        }
        booking.cancelled(BookingStatus.CANCELLED_CUSTOMER, fee, OffsetDateTime.now());
        return toResponse(bookings.save(booking), service, provider);
    }

    // MARK: Provider verbs

    /** A quote for a PRICE_ON_QUOTE booking. The number goes in the thread for
     *  the conversation and on the booking for the money. */
    @Transactional
    ServiceDtos.BookingResponse quote(UUID ownerUserId, UUID bookingId, long priceCents) {
        Provider provider = directory.requireMine(ownerUserId);
        Booking booking = requireProviders(provider, bookingId);
        requireStatus(booking, BookingStatus.REQUESTED);
        if (booking.getPaymentStatus() == BookingPaymentState.HELD) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "This booking is already paid — it can't be re-quoted");
        }
        booking.quoted(priceCents, OffsetDateTime.now());
        return toResponse(bookings.save(booking), serviceOf(booking), provider);
    }

    @Transactional
    ServiceDtos.BookingResponse confirm(UUID ownerUserId, UUID bookingId) {
        Provider provider = directory.requireMine(ownerUserId);
        Booking booking = requireProviders(provider, bookingId);
        requireStatus(booking, BookingStatus.REQUESTED);
        if (booking.getPriceCents() != null
            && booking.getPaymentStatus() != BookingPaymentState.HELD) {
            // A quoted booking confirms itself when the customer accepts; a
            // priced one held at request. Neither path arrives here unpaid.
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Waiting on the customer to accept the quote");
        }
        booking.confirmed(OffsetDateTime.now());
        ServiceOffering service = serviceOf(booking);
        events.publishEvent(new BookingConfirmed(booking.getId(), booking.getCustomerId(),
            service.getName(), booking.getStartsAt()));
        return toResponse(bookings.save(booking), service, provider);
    }

    @Transactional
    ServiceDtos.BookingResponse decline(UUID ownerUserId, UUID bookingId) {
        Provider provider = directory.requireMine(ownerUserId);
        Booking booking = requireProviders(provider, bookingId);
        requireStatus(booking, BookingStatus.REQUESTED);
        payments.release(booking, "Booking declined");
        booking.declined(OffsetDateTime.now());
        return toResponse(bookings.save(booking), serviceOf(booking), provider);
    }

    /** Provider cancel: always free to the customer (SPECS §7). */
    @Transactional
    ServiceDtos.BookingResponse cancelAsProvider(UUID ownerUserId, UUID bookingId) {
        Provider provider = directory.requireMine(ownerUserId);
        Booking booking = requireProviders(provider, bookingId);
        requireStatus(booking, BookingStatus.CONFIRMED);
        payments.release(booking, "Cancelled by the provider");
        booking.cancelled(BookingStatus.CANCELLED_PROVIDER, 0, OffsetDateTime.now());
        return toResponse(bookings.save(booking), serviceOf(booking), provider);
    }

    /** The work is done. The money waits out the CONFIG capture window before
     *  the settle sweep moves it — the customer's time to raise a problem. */
    @Transactional
    ServiceDtos.BookingResponse complete(UUID ownerUserId, UUID bookingId) {
        Provider provider = directory.requireMine(ownerUserId);
        Booking booking = requireProviders(provider, bookingId);
        requireStatus(booking, BookingStatus.CONFIRMED);
        booking.completed(OffsetDateTime.now());
        return toResponse(bookings.save(booking), serviceOf(booking), provider);
    }

    /** Nobody came. SPECS prices a no-show at 100%, and it settles now — there
     *  is no work to argue about, only an empty chair that was paid for. */
    @Transactional
    ServiceDtos.BookingResponse noShow(UUID ownerUserId, UUID bookingId) {
        Provider provider = directory.requireMine(ownerUserId);
        Booking booking = requireProviders(provider, bookingId);
        requireStatus(booking, BookingStatus.CONFIRMED);
        if (OffsetDateTime.now().isBefore(booking.getStartsAt())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "The appointment hasn't started yet");
        }
        payments.settle(booking, provider.getId(), provider.getDisplayName());
        booking.noShow(OffsetDateTime.now());
        return toResponse(bookings.save(booking), serviceOf(booking), provider);
    }

    // MARK: Jobs' verbs

    /** The confirm window ran out (CONFIG {@code services.booking.confirm.hours},
     *  24): auto-decline, auto-release (SPECS §7). */
    @Transactional
    void timeOut(UUID bookingId) {
        bookings.findById(bookingId).ifPresent(booking -> {
            if (booking.getStatus() != BookingStatus.REQUESTED) return;
            payments.release(booking, "The provider didn't answer in time");
            booking.declined(OffsetDateTime.now());
            bookings.save(booking);
        });
    }

    /** The capture window passed with no complaint: settle. */
    @Transactional
    void settleCompleted(UUID bookingId) {
        bookings.findById(bookingId).ifPresent(booking -> {
            if (booking.getStatus() != BookingStatus.COMPLETED
                || booking.getPaymentStatus() != BookingPaymentState.HELD) return;
            Provider provider = directory.require(booking.getProviderId());
            payments.settle(booking, provider.getId(), provider.getDisplayName());
            bookings.save(booking);
        });
    }

    // MARK: Reads

    @Transactional(readOnly = true)
    List<ServiceDtos.BookingResponse> mine(UUID me, int limit) {
        return decorate(bookings.findByCustomerIdOrderByRequestedAtDesc(me,
            PageRequest.of(0, Math.clamp(limit, 1, 100))));
    }

    @Transactional(readOnly = true)
    ServiceDtos.BookingResponse get(UUID me, UUID bookingId) {
        Booking booking = bookings.findById(bookingId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such booking"));
        Provider provider = directory.require(booking.getProviderId());
        if (!booking.getCustomerId().equals(me) && !provider.getOwnerUserId().equals(me)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such booking");
        }
        return toResponse(booking, serviceOf(booking), provider);
    }

    @Transactional(readOnly = true)
    List<ServiceDtos.BookingResponse> providerQueue(UUID ownerUserId, String status, int limit) {
        Provider provider = directory.requireMine(ownerUserId);
        PageRequest page = PageRequest.of(0, Math.clamp(limit, 1, 100));
        List<Booking> queue = status == null || status.isBlank()
            ? bookings.findByProviderIdOrderByStartsAtDesc(provider.getId(), page)
            : bookings.findByProviderIdAndStatusOrderByStartsAtAsc(provider.getId(),
                parseStatus(status), page);
        return decorate(queue);
    }

    // MARK: Plumbing

    private List<ServiceDtos.BookingResponse> decorate(List<Booking> page) {
        if (page.isEmpty()) return List.of();
        Map<UUID, ServiceOffering> services = offerings.findAllById(page.stream()
                .map(Booking::getServiceId).collect(Collectors.toSet())).stream()
            .collect(Collectors.toMap(ServiceOffering::getId, s -> s));
        return page.stream()
            .map(b -> toResponse(b, services.get(b.getServiceId()),
                directory.require(b.getProviderId())))
            .toList();
    }

    private Booking requireCustomer(UUID me, UUID bookingId) {
        return bookings.findById(bookingId)
            .filter(b -> b.getCustomerId().equals(me))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such booking"));
    }

    private Booking requireProviders(Provider provider, UUID bookingId) {
        return bookings.findById(bookingId)
            .filter(b -> b.getProviderId().equals(provider.getId()))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such booking"));
    }

    private ServiceOffering serviceOf(Booking booking) {
        return offerings.findById(booking.getServiceId()).orElse(null);
    }

    private static void requireStatus(Booking booking, BookingStatus expected) {
        if (booking.getStatus() != expected) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "The booking is " + booking.getStatus() + ", not " + expected);
        }
    }

    private static BookingStatus parseStatus(String status) {
        try {
            return BookingStatus.valueOf(status.trim().toUpperCase());
        } catch (IllegalArgumentException unknown) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Unknown status " + status);
        }
    }

    private static ConversationContext bookingContext(Booking booking, ServiceOffering service) {
        return new ConversationContext("booking", booking.getId().toString(),
            service.getName(), booking.getStartsAt().toString(), null);
    }

    /**
     * What cancelling <em>right now</em> would cost this customer.
     *
     * <p>The one number a client cannot work out for itself: it depends on the
     * booking's status, on whether a price has been agreed at all, and on two
     * CONFIG values the app has no way to read — and it changes on a clock,
     * crossing from nothing to half the price at a moment nobody taps.
     *
     * <p>It exists because the app was reading {@code cancellationFeeCents} as
     * if it were this, and that column is a <em>record of what was charged</em>,
     * written by {@link Booking#cancelled}. It is therefore zero on every
     * booking that has not been cancelled — so the confirmation dialog promised
     * "nothing will be charged" on a confirmed job an hour away, and then took
     * half the price. Found by requesting one and reading the button.
     */
    private long cancellationFeeIfCancelledNow(Booking booking) {
        // A request nobody has accepted costs nothing to withdraw: no price has
        // been agreed, and the provider has turned no work away for it.
        if (booking.getStatus() != BookingStatus.CONFIRMED || booking.getPriceCents() == null) {
            return 0;
        }
        long freeHours = Math.max(0, config.number("services.booking.cancel.free.hours", 24));
        long hoursLeft = Duration.between(OffsetDateTime.now(), booking.getStartsAt()).toHours();
        if (hoursLeft >= freeHours) {
            return 0;
        }
        long bps = Math.clamp(config.number("services.booking.cancel.fee.bps", 5000), 0, 10_000);
        return Math.floorDiv(booking.getPriceCents() * bps, 10_000);
    }

    private ServiceDtos.BookingResponse toResponse(Booking b, ServiceOffering service,
                                                   Provider provider) {
        return new ServiceDtos.BookingResponse(b.getId(), b.getServiceId(),
            service == null ? "Removed service" : service.getName(),
            b.getProviderId(),
            provider == null ? "Provider" : provider.getDisplayName(),
            b.getCustomerId(), b.getStatus().name(), b.getStartsAt(), b.getDurationMinutes(),
            b.getPriceCents(), payments.currency(), b.getPaymentStatus().name(), b.getNote(),
            b.getConversationId(), b.getCancellationFeeCents(),
            cancellationFeeIfCancelledNow(b), b.getRequestedAt(),
            b.getQuotedAt(), b.getConfirmedAt(), b.getCompletedAt(), b.getCancelledAt());
    }
}
