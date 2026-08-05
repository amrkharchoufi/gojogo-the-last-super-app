package com.gojogo.services.internal;

import com.gojogo.media.MediaDocumentApi;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.WalletApi;
import jakarta.validation.Valid;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * The provider's own surface — the services sibling of
 * {@code /v1/delivery/merchants/mine} and {@code /v1/economy/sellers/mine},
 * and the data plane GoJoAdmin calls with the owner's own JWT. Everything
 * resolves the practice from the caller, never from a path id.
 */
@RestController
class ProviderConsoleController {

    private final ServiceCatalogService catalog;
    private final AvailabilityService availability;
    private final BookingService bookings;
    private final ServiceReviewService reviews;
    private final ProviderDirectory directory;
    private final ProviderDocumentRepository documents;
    private final MediaDocumentApi privateMedia;
    private final WalletApi wallet;
    private final ServicesCurrentProfile current;

    ProviderConsoleController(ServiceCatalogService catalog, AvailabilityService availability,
                              BookingService bookings, ServiceReviewService reviews,
                              ProviderDirectory directory,
                              ProviderDocumentRepository documents,
                              MediaDocumentApi privateMedia, WalletApi wallet,
                              ServicesCurrentProfile current) {
        this.catalog = catalog;
        this.availability = availability;
        this.bookings = bookings;
        this.reviews = reviews;
        this.directory = directory;
        this.documents = documents;
        this.privateMedia = privateMedia;
        this.wallet = wallet;
        this.current = current;
    }

    // MARK: Profile

    @GetMapping("/v1/services/providers/mine")
    ServiceDtos.ProviderResponse mine(@AuthenticationPrincipal Jwt jwt) {
        return catalog.mine(current.require(jwt).id());
    }

    @PutMapping("/v1/services/providers/mine")
    ServiceDtos.ProviderResponse update(@AuthenticationPrincipal Jwt jwt,
                                        @Valid @RequestBody
                                        ServiceDtos.UpdateProviderRequest request) {
        return catalog.updateProfile(current.require(jwt).id(), request);
    }

    /** Balances + statement on the vertical's own surface — only the module
     *  that owns a payee can prove the caller owns it (ARCHITECTURE §10b). */
    @GetMapping("/v1/services/providers/mine/wallet")
    ProviderWalletResponse walletView(@AuthenticationPrincipal Jwt jwt,
                                      @RequestParam(defaultValue = "50") int limit) {
        Provider provider = directory.requireMine(current.require(jwt).id());
        return new ProviderWalletResponse(
            wallet.balancesOf(OwnerKind.MERCHANT, provider.getId()),
            wallet.statement(OwnerKind.MERCHANT, provider.getId(), Math.clamp(limit, 1, 200)));
    }

    record ProviderWalletResponse(WalletApi.Balances balances, List<WalletApi.Entry> entries) {
    }

    // MARK: Qualification papers (private)

    @PostMapping("/v1/services/providers/mine/documents/presign")
    MediaDocumentApi.DocumentUpload presignDocument(@AuthenticationPrincipal Jwt jwt,
                                                    @RequestParam(defaultValue = "application/pdf")
                                                    String contentType) {
        Provider provider = directory.requireMine(current.require(jwt).id());
        return privateMedia.presignDocumentUpload(provider.getId(), "provider", contentType);
    }

    @PostMapping("/v1/services/providers/mine/documents")
    @ResponseStatus(HttpStatus.CREATED)
    ServiceDtos.ProviderDocumentResponse attachDocument(
        @AuthenticationPrincipal Jwt jwt,
        @Valid @RequestBody ServiceDtos.AttachProviderDocumentRequest request) {
        Provider provider = directory.requireMine(current.require(jwt).id());
        ProviderDocument saved = documents.save(new ProviderDocument(provider.getId(),
            request.objectKey(), request.label()));
        return new ServiceDtos.ProviderDocumentResponse(saved.getId(), saved.getLabel(),
            null, saved.getUploadedAt());
    }

    @GetMapping("/v1/services/providers/mine/documents")
    List<ServiceDtos.ProviderDocumentResponse> myDocuments(@AuthenticationPrincipal Jwt jwt) {
        Provider provider = directory.requireMine(current.require(jwt).id());
        return documents.findByProviderIdOrderByUploadedAtAsc(provider.getId()).stream()
            .map(d -> new ServiceDtos.ProviderDocumentResponse(d.getId(), d.getLabel(),
                privateMedia.presignDocumentRead(d.getObjectKey()), d.getUploadedAt()))
            .toList();
    }

    // MARK: Catalog

    @GetMapping("/v1/services/providers/mine/services")
    List<ServiceDtos.ServiceResponse> myCatalog(@AuthenticationPrincipal Jwt jwt,
                                                @RequestParam(defaultValue = "100") int limit) {
        return catalog.mineCatalog(current.require(jwt).id(), limit);
    }

    @PostMapping("/v1/services/providers/mine/services")
    @ResponseStatus(HttpStatus.CREATED)
    ServiceDtos.ServiceResponse create(@AuthenticationPrincipal Jwt jwt,
                                       @Valid @RequestBody ServiceDtos.ServiceRequest request) {
        return catalog.create(current.require(jwt).id(), request);
    }

    @PutMapping("/v1/services/providers/mine/services/{serviceId}")
    ServiceDtos.ServiceResponse edit(@AuthenticationPrincipal Jwt jwt,
                                     @PathVariable UUID serviceId,
                                     @Valid @RequestBody ServiceDtos.ServiceRequest request) {
        return catalog.update(current.require(jwt).id(), serviceId, request);
    }

    @PutMapping("/v1/services/providers/mine/services/{serviceId}/active")
    ServiceDtos.ServiceResponse setActive(@AuthenticationPrincipal Jwt jwt,
                                          @PathVariable UUID serviceId,
                                          @RequestParam boolean active) {
        return catalog.setActive(current.require(jwt).id(), serviceId, active);
    }

    // MARK: Availability

    @GetMapping("/v1/services/providers/mine/availability")
    List<ServiceDtos.AvailabilityRuleResponse> myRules(@AuthenticationPrincipal Jwt jwt) {
        return availability.rulesFor(directory.requireMine(current.require(jwt).id()));
    }

    /** The whole template replaced at once — a calendar is edited as a whole. */
    @PutMapping("/v1/services/providers/mine/availability")
    List<ServiceDtos.AvailabilityRuleResponse> replaceRules(
        @AuthenticationPrincipal Jwt jwt,
        @Valid @RequestBody ServiceDtos.ReplaceAvailabilityRequest request) {
        return availability.replaceRules(directory.requireMine(current.require(jwt).id()),
            request.rules());
    }

    @GetMapping("/v1/services/providers/mine/availability/exceptions")
    List<LocalDate> myExceptions(@AuthenticationPrincipal Jwt jwt) {
        return availability.exceptionsFor(directory.requireMine(current.require(jwt).id()));
    }

    @PostMapping("/v1/services/providers/mine/availability/exceptions")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void addException(@AuthenticationPrincipal Jwt jwt,
                      @Valid @RequestBody ServiceDtos.ExceptionRequest request) {
        availability.addException(directory.requireMine(current.require(jwt).id()),
            request.onDate());
    }

    @DeleteMapping("/v1/services/providers/mine/availability/exceptions")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void removeException(@AuthenticationPrincipal Jwt jwt,
                         @RequestParam
                         @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate onDate) {
        availability.removeException(directory.requireMine(current.require(jwt).id()), onDate);
    }

    // MARK: Booking queue

    @GetMapping("/v1/services/providers/mine/bookings")
    List<ServiceDtos.BookingResponse> queue(@AuthenticationPrincipal Jwt jwt,
                                            @RequestParam(required = false) String status,
                                            @RequestParam(defaultValue = "50") int limit) {
        return bookings.providerQueue(current.require(jwt).id(), status, limit);
    }

    @PostMapping("/v1/services/providers/mine/bookings/{bookingId}/quote")
    ServiceDtos.BookingResponse quote(@AuthenticationPrincipal Jwt jwt,
                                      @PathVariable UUID bookingId,
                                      @Valid @RequestBody ServiceDtos.QuoteRequest request) {
        return bookings.quote(current.require(jwt).id(), bookingId, request.priceCents());
    }

    @PostMapping("/v1/services/providers/mine/bookings/{bookingId}/confirm")
    ServiceDtos.BookingResponse confirm(@AuthenticationPrincipal Jwt jwt,
                                        @PathVariable UUID bookingId) {
        return bookings.confirm(current.require(jwt).id(), bookingId);
    }

    @PostMapping("/v1/services/providers/mine/bookings/{bookingId}/decline")
    ServiceDtos.BookingResponse decline(@AuthenticationPrincipal Jwt jwt,
                                        @PathVariable UUID bookingId) {
        return bookings.decline(current.require(jwt).id(), bookingId);
    }

    @PostMapping("/v1/services/providers/mine/bookings/{bookingId}/cancel")
    ServiceDtos.BookingResponse cancel(@AuthenticationPrincipal Jwt jwt,
                                       @PathVariable UUID bookingId) {
        return bookings.cancelAsProvider(current.require(jwt).id(), bookingId);
    }

    @PostMapping("/v1/services/providers/mine/bookings/{bookingId}/complete")
    ServiceDtos.BookingResponse complete(@AuthenticationPrincipal Jwt jwt,
                                         @PathVariable UUID bookingId) {
        return bookings.complete(current.require(jwt).id(), bookingId);
    }

    @PostMapping("/v1/services/providers/mine/bookings/{bookingId}/no-show")
    ServiceDtos.BookingResponse noShow(@AuthenticationPrincipal Jwt jwt,
                                       @PathVariable UUID bookingId) {
        return bookings.noShow(current.require(jwt).id(), bookingId);
    }

    // MARK: Reviews

    @PostMapping("/v1/services/providers/mine/reviews/{reviewId}/reply")
    ServiceDtos.ServiceReviewResponse reply(@AuthenticationPrincipal Jwt jwt,
                                            @PathVariable UUID reviewId,
                                            @Valid @RequestBody
                                            ServiceDtos.ServiceReplyRequest request) {
        return reviews.reply(current.require(jwt).id(), reviewId, request.body());
    }
}
