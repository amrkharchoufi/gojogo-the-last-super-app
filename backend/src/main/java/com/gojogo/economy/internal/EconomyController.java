package com.gojogo.economy.internal;

import jakarta.validation.Valid;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

@RestController
class EconomyController {

    private final ListingService listings;
    private final EconomyCurrentProfile current;

    EconomyController(ListingService listings, EconomyCurrentProfile current) {
        this.listings = listings;
        this.current = current;
    }

    @GetMapping("/v1/economy/listings")
    ListingPageResponse browse(@AuthenticationPrincipal Jwt jwt,
                               @RequestParam(required = false) String category,
                               @RequestParam(required = false)
                               @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) OffsetDateTime before,
                               @RequestParam(defaultValue = "20") int limit) {
        return listings.browse(current.require(jwt).id(), category, before, limit);
    }

    @GetMapping("/v1/economy/listings/mine")
    List<ListingResponse> mine(@AuthenticationPrincipal Jwt jwt,
                               @RequestParam(defaultValue = "50") int limit) {
        return listings.mine(current.require(jwt).id(), limit);
    }

    @GetMapping("/v1/economy/saved")
    List<ListingResponse> saved(@AuthenticationPrincipal Jwt jwt,
                                @RequestParam(defaultValue = "50") int limit) {
        return listings.saved(current.require(jwt).id(), limit);
    }

    @GetMapping("/v1/economy/listings/{listingId}")
    ListingResponse get(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID listingId) {
        return listings.get(current.require(jwt).id(), listingId);
    }

    @PostMapping("/v1/economy/listings")
    @ResponseStatus(HttpStatus.CREATED)
    ListingResponse create(@AuthenticationPrincipal Jwt jwt,
                           @Valid @RequestBody CreateListingRequest request) {
        return listings.create(current.require(jwt).id(), request);
    }

    @DeleteMapping("/v1/economy/listings/{listingId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void delete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID listingId) {
        listings.delete(current.require(jwt).id(), listingId);
    }

    /** Buyer taps "Message seller": returns the thread to open (created on first
     *  ask, reused after) and a ready-made opener. Sends nothing by itself. */
    @PostMapping("/v1/economy/listings/{listingId}/chat")
    ListingChatResponse chat(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID listingId) {
        return listings.openChat(current.require(jwt).id(), listingId);
    }

    @PostMapping("/v1/economy/listings/{listingId}/save")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void save(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID listingId) {
        listings.save(current.require(jwt).id(), listingId);
    }

    @DeleteMapping("/v1/economy/listings/{listingId}/save")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void unsave(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID listingId) {
        listings.unsave(current.require(jwt).id(), listingId);
    }
}
