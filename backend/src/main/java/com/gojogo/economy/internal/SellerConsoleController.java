package com.gojogo.economy.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.PayoutApi;
import com.gojogo.payments.WalletApi;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
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
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * The seller's own surface — the economy sibling of
 * {@code /v1/delivery/merchants/mine}, and the data plane GoJoAdmin's Economy
 * module calls with the owner's own JWT (ARCHITECTURE §10b: no admin-only
 * mirror). Everything here resolves the shop from the caller, never from a
 * path id.
 */
@RestController
class SellerConsoleController {

    /** Payments owns the number; this only has to show it before the seller
     *  taps something that would be refused for being under it. */
    private static final String PAYOUT_MIN_KEY = "payments.payout.min.minor";
    private static final long PAYOUT_MIN_DEFAULT = 1_000;

    private final SellerRegistry registry;
    private final SellerRepository sellers;
    private final ProductCatalogService catalog;
    private final ProductCheckoutService checkout;
    private final ProductPromotionService promotions;
    private final ProductReviewService reviews;
    private final ProductOrderPayments payments;
    private final WalletApi wallet;
    private final PayoutApi payouts;
    private final ConfigApi config;
    private final EconomyCurrentProfile current;

    SellerConsoleController(SellerRegistry registry, SellerRepository sellers,
                            ProductCatalogService catalog, ProductCheckoutService checkout,
                            ProductPromotionService promotions, ProductReviewService reviews,
                            ProductOrderPayments payments, WalletApi wallet,
                            PayoutApi payouts, ConfigApi config,
                            EconomyCurrentProfile current) {
        this.registry = registry;
        this.sellers = sellers;
        this.catalog = catalog;
        this.checkout = checkout;
        this.promotions = promotions;
        this.reviews = reviews;
        this.payments = payments;
        this.wallet = wallet;
        this.payouts = payouts;
        this.config = config;
        this.current = current;
    }

    @GetMapping("/v1/economy/sellers/mine")
    ProductDtos.SellerResponse mine(@AuthenticationPrincipal Jwt jwt) {
        return toResponse(registry.requireMine(current.require(jwt).id()));
    }

    @PutMapping("/v1/economy/sellers/mine")
    @Transactional
    ProductDtos.SellerResponse update(@AuthenticationPrincipal Jwt jwt,
                                      @Valid @RequestBody ProductDtos.UpdateSellerRequest request) {
        Seller seller = registry.requireMine(current.require(jwt).id());
        seller.configure(request.displayName().trim(), request.logoUrl(),
            request.shippingFlatCents(), request.freeShippingOverCents(), request.taxBps());
        return toResponse(sellers.save(seller));
    }

    /** Balances + statement + the way out, on the vertical's own surface — only
     *  the module that owns a payee can prove the caller owns it
     *  (ARCHITECTURE §10b). */
    @GetMapping("/v1/economy/sellers/mine/wallet")
    SellerWalletResponse walletView(@AuthenticationPrincipal Jwt jwt,
                                    @RequestParam(defaultValue = "50") int limit) {
        Seller seller = registry.requireMine(current.require(jwt).id());
        PayoutApi.ConnectStatus connect = payouts.statusOf(OwnerKind.MERCHANT, seller.getId());
        return new SellerWalletResponse(
            wallet.balancesOf(OwnerKind.MERCHANT, seller.getId()),
            wallet.statement(OwnerKind.MERCHANT, seller.getId(), Math.clamp(limit, 1, 200)),
            payouts.isConfigured(), connect.exists(), connect.ready(),
            connect.requirementsNote(), config.number(PAYOUT_MIN_KEY, PAYOUT_MIN_DEFAULT));
    }

    /**
     * A Stripe-hosted onboarding link for this shop's payouts. Single-use and
     * short-lived by Stripe's design, so it is minted on demand and never
     * stored: whoever opens it is treated as the account holder.
     */
    @PostMapping("/v1/economy/sellers/mine/payouts/onboarding-link")
    Map<String, String> payoutOnboardingLink(@AuthenticationPrincipal Jwt jwt) {
        Seller seller = registry.requireMine(current.require(jwt).id());
        return Map.of("url", payouts.onboardingLink(OwnerKind.MERCHANT, seller.getId(),
            jwt.getClaimAsString("email")));
    }

    /**
     * Sends the shop's earnings to its connected account.
     *
     * <p>Deliberately not {@code @Transactional}: a payout is two transactions
     * on purpose (debit, then transfer), and a third wrapping them would undo
     * that — a crash mid-transfer would roll the debit back and leave money that
     * may already be in flight looking as though it never left.
     *
     * <p>No earned-cap guard: a shop's balance is only ever settled sales, never
     * a card top-up, so there is no card-in/bank-out path to bound. The minimum
     * and the cooldown still run under the payout's own lock.
     */
    @PostMapping("/v1/economy/sellers/mine/payouts")
    SellerPayoutResponse payOut(@AuthenticationPrincipal Jwt jwt,
                                @Valid @RequestBody SellerPayoutRequest request) {
        UUID me = current.require(jwt).id();
        Seller seller = registry.requireMine(me);
        PayoutApi.PayoutResult result = payouts.payOut(OwnerKind.MERCHANT, seller.getId(), me,
            request.amountMinor(), PayoutApi.PayoutGuard.none());
        return new SellerPayoutResponse(result.payoutId(), result.amountMinor(),
            result.currency(), result.status(), result.failureReason());
    }

    /**
     * @param payoutsAvailable  whether the platform has Stripe wired up at all —
     *                          false means the balance is real and the door is
     *                          simply not open yet, which is a different sentence
     *                          than "you haven't set this up"
     * @param payoutsConfigured this shop has started onboarding
     * @param payoutsReady      Stripe will accept a transfer for it
     */
    record SellerWalletResponse(WalletApi.Balances balances, List<WalletApi.Entry> entries,
                                boolean payoutsAvailable, boolean payoutsConfigured,
                                boolean payoutsReady, String payoutsRequirement,
                                long payoutMinMinor) {
    }

    record SellerPayoutRequest(@Min(1) long amountMinor) {
    }

    /** {@code status} is REQUESTED / SENT / FAILED — a payout the provider
     *  refused is reported, not hidden, and its debit has already been put back. */
    record SellerPayoutResponse(UUID id, long amountMinor, String currency, String status,
                                String failureReason) {
    }

    // MARK: Catalog

    @GetMapping("/v1/economy/sellers/mine/products")
    List<ProductDtos.ProductResponse> myProducts(@AuthenticationPrincipal Jwt jwt,
                                                 @RequestParam(defaultValue = "100") int limit) {
        return catalog.mine(current.require(jwt).id(), limit);
    }

    @PostMapping("/v1/economy/sellers/mine/products")
    @ResponseStatus(HttpStatus.CREATED)
    ProductDtos.ProductResponse create(@AuthenticationPrincipal Jwt jwt,
                                       @Valid @RequestBody ProductDtos.CreateProductRequest request) {
        return catalog.create(current.require(jwt).id(), request);
    }

    @PutMapping("/v1/economy/sellers/mine/products/{productId}")
    ProductDtos.ProductResponse edit(@AuthenticationPrincipal Jwt jwt,
                                     @PathVariable UUID productId,
                                     @Valid @RequestBody ProductDtos.CreateProductRequest request) {
        return catalog.update(current.require(jwt).id(), productId, request);
    }

    @PutMapping("/v1/economy/sellers/mine/products/{productId}/active")
    ProductDtos.ProductResponse setActive(@AuthenticationPrincipal Jwt jwt,
                                          @PathVariable UUID productId,
                                          @RequestParam boolean active) {
        return catalog.setActive(current.require(jwt).id(), productId, active);
    }

    // MARK: Orders

    @GetMapping("/v1/economy/sellers/mine/orders")
    List<ProductDtos.OrderResponse> orderQueue(@AuthenticationPrincipal Jwt jwt,
                                               @RequestParam(required = false) String status,
                                               @RequestParam(defaultValue = "50") int limit) {
        return checkout.sellerQueue(current.require(jwt).id(), status, limit);
    }

    @PostMapping("/v1/economy/sellers/mine/orders/{orderId}/ship")
    ProductDtos.OrderResponse ship(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID orderId,
                                   @Valid @RequestBody ProductDtos.ShipRequest request) {
        return checkout.ship(current.require(jwt).id(), orderId, request.trackingNote());
    }

    @PostMapping("/v1/economy/sellers/mine/orders/{orderId}/cancel")
    ProductDtos.OrderResponse cancel(@AuthenticationPrincipal Jwt jwt,
                                     @PathVariable UUID orderId) {
        return checkout.cancelAsSeller(current.require(jwt).id(), orderId);
    }

    // MARK: Promotions

    @GetMapping("/v1/economy/sellers/mine/promotions")
    List<ProductDtos.PromotionResponse> myPromotions(@AuthenticationPrincipal Jwt jwt) {
        return promotions.mine(registry.requireMine(current.require(jwt).id()));
    }

    @PostMapping("/v1/economy/sellers/mine/promotions")
    @ResponseStatus(HttpStatus.CREATED)
    ProductDtos.PromotionResponse createPromotion(
        @AuthenticationPrincipal Jwt jwt,
        @Valid @RequestBody ProductDtos.CreatePromotionRequest request) {
        return promotions.create(registry.requireMine(current.require(jwt).id()), request);
    }

    /** Deactivation, not deletion: redemptions reference it forever. */
    @DeleteMapping("/v1/economy/sellers/mine/promotions/{promotionId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void deactivatePromotion(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID promotionId) {
        promotions.deactivate(registry.requireMine(current.require(jwt).id()), promotionId);
    }

    // MARK: Reviews

    @PostMapping("/v1/economy/sellers/mine/reviews/{reviewId}/reply")
    ProductDtos.ReviewResponse replyToReview(@AuthenticationPrincipal Jwt jwt,
                                             @PathVariable UUID reviewId,
                                             @Valid @RequestBody ProductDtos.ReplyRequest request) {
        return reviews.reply(current.require(jwt).id(), reviewId, request.body());
    }

    private ProductDtos.SellerResponse toResponse(Seller seller) {
        return new ProductDtos.SellerResponse(seller.getId(), seller.getDisplayName(),
            seller.getLogoUrl(), seller.getShippingFlatCents(),
            seller.getFreeShippingOverCents(), seller.getTaxBps(), seller.isSuspended(),
            payments.currency());
    }
}
