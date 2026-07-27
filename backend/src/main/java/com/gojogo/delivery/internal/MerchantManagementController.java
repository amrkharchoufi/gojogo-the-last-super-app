package com.gojogo.delivery.internal;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/**
 * The restaurant owner's endpoints, all scoped to <em>their</em> restaurant —
 * hence {@code /mine} rather than an id in the path. There is no way to name
 * someone else's merchant here, so there is nothing to authorise beyond "do you
 * own one", and a caller who doesn't gets a 404 either way.
 *
 * <p>Every mutation answers with the whole restaurant, menu included. A menu
 * editor changes one dish and re-renders the list around it, and one response
 * keeps the client from having to reconcile a partial write.
 */
@RestController
class MerchantManagementController {

    private final MerchantManagementService merchants;
    private final DeliveryCurrentProfile current;

    MerchantManagementController(MerchantManagementService merchants,
                                 DeliveryCurrentProfile current) {
        this.merchants = merchants;
        this.current = current;
    }

    @GetMapping("/v1/delivery/merchants/mine")
    MyMerchantDto mine(@AuthenticationPrincipal Jwt jwt) {
        return merchants.mine(current.require(jwt).id());
    }

    @PutMapping("/v1/delivery/merchants/mine")
    MyMerchantDto update(@AuthenticationPrincipal Jwt jwt,
                         @Valid @RequestBody UpdateMerchantRequest request) {
        return merchants.update(current.require(jwt).id(), request);
    }

    /** Open or close the restaurant. Opening an empty menu is a 409. */
    @PutMapping("/v1/delivery/merchants/mine/open")
    MyMerchantDto setOpen(@AuthenticationPrincipal Jwt jwt,
                          @RequestBody SetOpenRequest request) {
        return merchants.setOpen(current.require(jwt).id(), request.open());
    }

    @PostMapping("/v1/delivery/merchants/mine/sections")
    @ResponseStatus(HttpStatus.CREATED)
    MyMerchantDto addSection(@AuthenticationPrincipal Jwt jwt,
                             @Valid @RequestBody MenuSectionRequest request) {
        return merchants.addSection(current.require(jwt).id(), request);
    }

    @PutMapping("/v1/delivery/merchants/mine/sections/{sectionId}")
    MyMerchantDto renameSection(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID sectionId,
                                @Valid @RequestBody MenuSectionRequest request) {
        return merchants.renameSection(current.require(jwt).id(), sectionId, request);
    }

    @DeleteMapping("/v1/delivery/merchants/mine/sections/{sectionId}")
    MyMerchantDto deleteSection(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID sectionId) {
        return merchants.deleteSection(current.require(jwt).id(), sectionId);
    }

    @PostMapping("/v1/delivery/merchants/mine/sections/{sectionId}/items")
    @ResponseStatus(HttpStatus.CREATED)
    MyMerchantDto addItem(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID sectionId,
                          @Valid @RequestBody MenuItemRequest request) {
        return merchants.addItem(current.require(jwt).id(), sectionId, request);
    }

    @PutMapping("/v1/delivery/merchants/mine/items/{itemId}")
    MyMerchantDto updateItem(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID itemId,
                             @Valid @RequestBody MenuItemRequest request) {
        return merchants.updateItem(current.require(jwt).id(), itemId, request);
    }

    @DeleteMapping("/v1/delivery/merchants/mine/items/{itemId}")
    MyMerchantDto deleteItem(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID itemId) {
        return merchants.deleteItem(current.require(jwt).id(), itemId);
    }
}
