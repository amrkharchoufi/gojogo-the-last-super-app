package com.gojogo.services.internal;

import jakarta.validation.Valid;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/** The customer's side: browse, provider pages, slots, bookings, reviews. */
@RestController
class ServicesController {

    private final ServiceCatalogService catalog;
    private final AvailabilityService availability;
    private final BookingService bookingService;
    private final ServiceReviewService reviews;
    private final ProviderDirectory directory;
    private final ServiceOfferingRepository offerings;
    private final ServicesCurrentProfile current;

    ServicesController(ServiceCatalogService catalog, AvailabilityService availability,
                       BookingService bookingService, ServiceReviewService reviews,
                       ProviderDirectory directory, ServiceOfferingRepository offerings,
                       ServicesCurrentProfile current) {
        this.catalog = catalog;
        this.availability = availability;
        this.bookingService = bookingService;
        this.reviews = reviews;
        this.directory = directory;
        this.offerings = offerings;
        this.current = current;
    }

    @GetMapping("/v1/services")
    ServiceDtos.ServicePageResponse browse(@AuthenticationPrincipal Jwt jwt,
                                           @RequestParam(required = false) String category,
                                           @RequestParam(required = false) UUID providerId,
                                           @RequestParam(required = false)
                                           @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) OffsetDateTime before,
                                           @RequestParam(defaultValue = "20") int limit) {
        current.require(jwt);
        return catalog.browse(category, providerId, before, limit);
    }

    @GetMapping("/v1/services/providers/{providerId}")
    ServiceDtos.ProviderResponse provider(@AuthenticationPrincipal Jwt jwt,
                                          @PathVariable UUID providerId) {
        current.require(jwt);
        return catalog.publicProfile(providerId);
    }

    @GetMapping("/v1/services/{serviceId}")
    ServiceDtos.ServiceResponse get(@AuthenticationPrincipal Jwt jwt,
                                    @PathVariable UUID serviceId) {
        return catalog.get(current.require(jwt).id(), serviceId);
    }

    /** The offerable start times — template − exceptions − bookings − buffer. */
    @GetMapping("/v1/services/{serviceId}/slots")
    ServiceDtos.SlotsResponse slots(@AuthenticationPrincipal Jwt jwt,
                                    @PathVariable UUID serviceId,
                                    @RequestParam(required = false)
                                    @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                                    @RequestParam(defaultValue = "7") int days) {
        UUID me = current.require(jwt).id();
        ServiceDtos.ServiceResponse service = catalog.get(me, serviceId);
        Provider provider = directory.require(service.providerId());
        ServiceOffering offering = offerings.findById(serviceId).orElseThrow();
        return new ServiceDtos.SlotsResponse(serviceId, service.durationMinutes(),
            provider.getTimezone(), availability.slots(provider, offering, from, days));
    }

    @GetMapping("/v1/services/{serviceId}/reviews")
    List<ServiceDtos.ServiceReviewResponse> serviceReviews(@AuthenticationPrincipal Jwt jwt,
                                                           @PathVariable UUID serviceId,
                                                           @RequestParam(defaultValue = "50") int limit) {
        current.require(jwt);
        return reviews.forService(serviceId, limit);
    }

    @PostMapping("/v1/services/{serviceId}/reviews")
    @ResponseStatus(HttpStatus.CREATED)
    ServiceDtos.ServiceReviewResponse review(@AuthenticationPrincipal Jwt jwt,
                                             @PathVariable UUID serviceId,
                                             @Valid @RequestBody
                                             ServiceDtos.CreateServiceReviewRequest request) {
        return reviews.create(current.require(jwt).id(), serviceId, request);
    }

    // MARK: Bookings

    @PostMapping("/v1/services/bookings")
    @ResponseStatus(HttpStatus.CREATED)
    ServiceDtos.BookingResponse book(@AuthenticationPrincipal Jwt jwt,
                                     @Valid @RequestBody ServiceDtos.BookingRequestBody body) {
        return bookingService.request(current.require(jwt).id(), body);
    }

    @GetMapping("/v1/services/bookings")
    List<ServiceDtos.BookingResponse> myBookings(@AuthenticationPrincipal Jwt jwt,
                                                 @RequestParam(defaultValue = "50") int limit) {
        return bookingService.mine(current.require(jwt).id(), limit);
    }

    @GetMapping("/v1/services/bookings/{bookingId}")
    ServiceDtos.BookingResponse booking(@AuthenticationPrincipal Jwt jwt,
                                        @PathVariable UUID bookingId) {
        return bookingService.get(current.require(jwt).id(), bookingId);
    }

    /** Accepting the provider's quote pays and confirms in one act. */
    @PostMapping("/v1/services/bookings/{bookingId}/accept-quote")
    ServiceDtos.BookingResponse acceptQuote(@AuthenticationPrincipal Jwt jwt,
                                            @PathVariable UUID bookingId) {
        return bookingService.acceptQuote(current.require(jwt).id(), bookingId);
    }

    @PostMapping("/v1/services/bookings/{bookingId}/cancel")
    ServiceDtos.BookingResponse cancel(@AuthenticationPrincipal Jwt jwt,
                                       @PathVariable UUID bookingId) {
        return bookingService.cancelAsCustomer(current.require(jwt).id(), bookingId);
    }
}
