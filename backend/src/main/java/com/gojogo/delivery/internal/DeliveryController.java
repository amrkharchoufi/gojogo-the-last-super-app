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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
class DeliveryController {

    private final DeliveryService delivery;
    private final DeliveryCurrentProfile current;

    DeliveryController(DeliveryService delivery, DeliveryCurrentProfile current) {
        this.delivery = delivery;
        this.current = current;
    }

    @GetMapping("/v1/delivery/merchants")
    List<MerchantDto> merchants(@RequestParam(required = false) String category,
                                @RequestParam(required = false) String q,
                                @RequestParam(defaultValue = "30") int limit) {
        return delivery.browse(category, q, limit);
    }

    /** Restaurant detail — the only response carrying the menu. */
    @GetMapping("/v1/delivery/merchants/{merchantId}")
    MerchantDto merchant(@PathVariable UUID merchantId) {
        return delivery.merchant(merchantId);
    }

    @GetMapping("/v1/delivery/addresses")
    List<AddressDto> addresses(@AuthenticationPrincipal Jwt jwt) {
        return delivery.addresses(current.require(jwt).id());
    }

    @PostMapping("/v1/delivery/addresses")
    @ResponseStatus(HttpStatus.CREATED)
    AddressDto createAddress(@AuthenticationPrincipal Jwt jwt,
                             @Valid @RequestBody SaveAddressRequest request) {
        return delivery.createAddress(current.require(jwt).id(), request);
    }

    @PutMapping("/v1/delivery/addresses/{addressId}")
    AddressDto updateAddress(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID addressId,
                             @Valid @RequestBody SaveAddressRequest request) {
        return delivery.updateAddress(current.require(jwt).id(), addressId, request);
    }

    @PostMapping("/v1/delivery/addresses/{addressId}/default")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void makeDefaultAddress(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID addressId) {
        delivery.makeDefaultAddress(current.require(jwt).id(), addressId);
    }

    @DeleteMapping("/v1/delivery/addresses/{addressId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void deleteAddress(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID addressId) {
        delivery.deleteAddress(current.require(jwt).id(), addressId);
    }

    /**
     * What a basket would cost, without placing it — including whether the
     * caller's wallet covers it, so the app can offer a top-up instead of
     * walking someone into a 402 at checkout.
     */
    @PostMapping("/v1/delivery/orders/quote")
    QuoteDto quote(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody QuoteRequest request) {
        return delivery.quote(current.require(jwt).id(), request);
    }

    /** Places the order and holds its total in the customer's own escrow.
     *  <b>402</b> when the wallet is short. */
    @PostMapping("/v1/delivery/orders")
    @ResponseStatus(HttpStatus.CREATED)
    OrderDto place(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody PlaceOrderRequest request) {
        return delivery.place(current.require(jwt).id(), request);
    }

    /** The promotions a customer could use here. */
    @GetMapping("/v1/delivery/merchants/{merchantId}/promotions")
    List<PromotionDto> promotions(@PathVariable UUID merchantId) {
        return delivery.livePromotions(merchantId);
    }

    /** The order being tracked right now, or {@code {"order": null}}. */
    @GetMapping("/v1/delivery/orders/active")
    ActiveOrderResponse active(@AuthenticationPrincipal Jwt jwt) {
        return delivery.active(current.require(jwt).id());
    }

    @GetMapping("/v1/delivery/orders")
    List<OrderDto> history(@AuthenticationPrincipal Jwt jwt,
                           @RequestParam(defaultValue = "20") int limit) {
        return delivery.history(current.require(jwt).id(), limit);
    }

    @GetMapping("/v1/delivery/orders/{orderId}")
    OrderDto get(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID orderId) {
        return delivery.get(current.require(jwt).id(), orderId);
    }

    @PostMapping("/v1/delivery/orders/{orderId}/cancel")
    OrderDto cancel(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID orderId) {
        return delivery.cancel(current.require(jwt).id(), orderId);
    }

    /**
     * How the food should be handed over — {@code PIN}, {@code PHOTO} or
     * {@code CONFIRM} — changeable right up until it is.
     *
     * <p>Contactless is a decision people make when the courier is already
     * close, which is why this is not a checkout-only field. <b>409</b> once the
     * order is finished; an unrecognised word is the configured default rather
     * than a 400, because a one-tap control that can return an error is a
     * control that looks broken.
     */
    @PostMapping("/v1/delivery/orders/{orderId}/handoff-mode")
    OrderDto setHandoffMode(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID orderId,
                            @Valid @RequestBody(required = false) HandoffModeRequest request) {
        return delivery.setHandoffMode(current.require(jwt).id(), orderId,
            request == null ? null : request.mode());
    }

    @PostMapping("/v1/delivery/orders/{orderId}/rate")
    OrderDto rate(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID orderId,
                  @Valid @RequestBody RateOrderRequest request) {
        return delivery.rate(current.require(jwt).id(), orderId, request.rating());
    }

    /** Tips after the food arrived. 100% goes to whoever delivered it. */
    @PostMapping("/v1/delivery/orders/{orderId}/tip")
    OrderDto tip(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID orderId,
                 @Valid @RequestBody TipRequest request) {
        return delivery.tip(current.require(jwt).id(), orderId, request.tipCents());
    }
}
