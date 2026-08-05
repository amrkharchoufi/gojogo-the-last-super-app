package com.gojogo.economy.internal;

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

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/**
 * The buyer's side of the merchant catalog: browse, product page, reviews,
 * checkout and their orders. The seller's side is
 * {@link SellerConsoleController}.
 */
@RestController
class ProductController {

    private final ProductCatalogService catalog;
    private final ProductCheckoutService checkout;
    private final ProductReviewService reviews;
    private final EconomyCurrentProfile current;

    ProductController(ProductCatalogService catalog, ProductCheckoutService checkout,
                      ProductReviewService reviews, EconomyCurrentProfile current) {
        this.catalog = catalog;
        this.checkout = checkout;
        this.reviews = reviews;
        this.current = current;
    }

    @GetMapping("/v1/economy/products")
    ProductDtos.ProductPageResponse browse(@AuthenticationPrincipal Jwt jwt,
                                           @RequestParam(required = false) String category,
                                           @RequestParam(required = false) UUID sellerId,
                                           @RequestParam(required = false)
                                           @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) OffsetDateTime before,
                                           @RequestParam(defaultValue = "20") int limit) {
        current.require(jwt);
        return catalog.browse(category, sellerId, before, limit);
    }

    @GetMapping("/v1/economy/products/{productId}")
    ProductDtos.ProductResponse get(@AuthenticationPrincipal Jwt jwt,
                                    @PathVariable UUID productId) {
        return catalog.get(current.require(jwt).id(), productId);
    }

    @GetMapping("/v1/economy/products/{productId}/reviews")
    List<ProductDtos.ReviewResponse> productReviews(@AuthenticationPrincipal Jwt jwt,
                                                    @PathVariable UUID productId,
                                                    @RequestParam(defaultValue = "50") int limit) {
        current.require(jwt);
        return reviews.forProduct(productId, limit);
    }

    /** Verified-purchase only: the body names the completed order this rides on. */
    @PostMapping("/v1/economy/products/{productId}/reviews")
    @ResponseStatus(HttpStatus.CREATED)
    ProductDtos.ReviewResponse review(@AuthenticationPrincipal Jwt jwt,
                                      @PathVariable UUID productId,
                                      @Valid @RequestBody ProductDtos.CreateReviewRequest request) {
        return reviews.create(current.require(jwt).id(), productId, request);
    }

    // MARK: Checkout + my orders

    @PostMapping("/v1/economy/orders")
    @ResponseStatus(HttpStatus.CREATED)
    ProductDtos.OrderResponse checkout(@AuthenticationPrincipal Jwt jwt,
                                       @Valid @RequestBody ProductDtos.CheckoutRequest request) {
        return checkout.checkout(current.require(jwt).id(), request);
    }

    @GetMapping("/v1/economy/orders")
    List<ProductDtos.OrderResponse> myOrders(@AuthenticationPrincipal Jwt jwt,
                                             @RequestParam(defaultValue = "50") int limit) {
        return checkout.mine(current.require(jwt).id(), limit);
    }

    @GetMapping("/v1/economy/orders/{orderId}")
    ProductDtos.OrderResponse order(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID orderId) {
        return checkout.get(current.require(jwt).id(), orderId);
    }

    /** "It arrived" — the tap that moves the money. */
    @PostMapping("/v1/economy/orders/{orderId}/received")
    ProductDtos.OrderResponse received(@AuthenticationPrincipal Jwt jwt,
                                       @PathVariable UUID orderId) {
        return checkout.confirmReceived(current.require(jwt).id(), orderId);
    }

    @PostMapping("/v1/economy/orders/{orderId}/cancel")
    ProductDtos.OrderResponse cancel(@AuthenticationPrincipal Jwt jwt,
                                     @PathVariable UUID orderId) {
        return checkout.cancelAsBuyer(current.require(jwt).id(), orderId);
    }
}
