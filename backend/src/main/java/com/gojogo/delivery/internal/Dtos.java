package com.gojogo.delivery.internal;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

record MenuItemDto(UUID id, String name, String detail, int priceCents,
                   String imageUrl, boolean popular) {
}

record MenuSectionDto(UUID id, String name, List<MenuItemDto> items) {
}

/** A restaurant. {@code menu} is empty in browse results and filled on detail. */
record MerchantDto(UUID id, String name, String cuisine, double rating, int reviewCount,
                   int etaMinutes, int deliveryFeeCents, String imageUrl, String promo,
                   List<String> tags, List<String> categories,
                   double latitude, double longitude, List<MenuSectionDto> menu) {
}

// MARK: The owner's view of their own restaurant (MerchantManagementService)

/** Like {@link MenuItemDto} but with {@code available} — a sold-out dish is
 *  hidden from customers and is exactly what its owner needs to see. */
record MyMenuItemDto(UUID id, String name, String detail, int priceCents,
                     String imageUrl, boolean popular, boolean available) {
}

record MyMenuSectionDto(UUID id, String name, List<MyMenuItemDto> items) {
}

/**
 * The restaurant as its owner sees it. {@code open} is their own switch;
 * {@code suspended} is the platform's, and only one of the two is theirs to
 * change. Rating and review count are shown but never sent back — they're
 * earned, not edited.
 */
record MyMerchantDto(UUID id, String name, String cuisine, String imageUrl, String promo,
                     int etaMinutes, int deliveryFeeCents, double rating, int reviewCount,
                     double latitude, double longitude,
                     List<String> categories, List<String> tags,
                     boolean open, boolean suspended, List<MyMenuSectionDto> menu) {
}

record UpdateMerchantRequest(@NotBlank @Size(max = 120) String name,
                             @NotBlank @Size(max = 80) String cuisine,
                             @Size(max = 600) String imageUrl,
                             @Size(max = 60) String promo,
                             @Min(5) @Max(180) int etaMinutes,
                             @Min(0) @Max(100_000) int deliveryFeeCents,
                             Double latitude, Double longitude,
                             @Size(max = 8) List<@Size(max = 40) String> categories,
                             @Size(max = 8) List<@Size(max = 40) String> tags) {
}

record MenuSectionRequest(@NotBlank @Size(max = 80) String name) {
}

/** {@code sectionId} is only read on update, where it moves a dish to another
 *  section; on create the section comes from the path. */
record MenuItemRequest(@NotBlank @Size(max = 120) String name,
                       @Size(max = 240) String detail,
                       @Min(0) @Max(10_000_000) int priceCents,
                       @Size(max = 600) String imageUrl,
                       boolean popular, boolean available,
                       UUID sectionId) {
}

record SetOpenRequest(boolean open) {
}

record OrderMerchantDto(UUID id, String name, String imageUrl, double latitude, double longitude) {
}

record CourierDto(String name, String vehicle, double rating, int deliveries) {
}

record OrderLineDto(UUID menuItemId, String name, int unitPriceCents, int qty) {
}

/** A saved delivery address. */
record AddressDto(UUID id, String label, String line1, String note,
                  Double latitude, Double longitude, boolean isDefault) {
}

/** Where an order actually went — a copy taken at order time, so editing or
 *  deleting the saved address never rewrites the receipt. */
record OrderAddressDto(UUID id, String label, String line1, String note,
                       Double latitude, Double longitude) {
}

record SaveAddressRequest(@Size(max = 40) String label,
                          @NotBlank @Size(max = 160) String line1,
                          @Size(max = 120) String note,
                          Double latitude, Double longitude,
                          boolean makeDefault) {
}

/**
 * A placed order as the app sees it. {@code etaMinutes} and {@code courierProgress}
 * are derived server-side from the fulfilment timeline, so two devices watching
 * the same order agree and a reinstall picks the countdown back up.
 */
record OrderDto(UUID id, OrderMerchantDto merchant, String status, int etaMinutes,
                double courierProgress, CourierDto courier, List<OrderLineDto> lines,
                int subtotalCents, int deliveryFeeCents, int serviceFeeCents, int totalCents,
                int discountCents, int tipCents, String promotionCode,
                String paymentStatus,
                String currency, String addressLabel, OrderAddressDto address, String note,
                Integer rating,
                OffsetDateTime placedAt, OffsetDateTime statusChangedAt, OffsetDateTime etaAt) {
}

/**
 * What a basket would cost, before anything is placed or charged.
 *
 * <p>Exists so the app can show a total the customer agrees to <em>before</em>
 * their wallet is touched — including whether they can actually afford it, which
 * is the difference between offering a top-up and showing them a 402.
 */
record QuoteDto(int subtotalCents, int deliveryFeeCents, int serviceFeeCents,
                int discountCents, int tipCents, int totalCents, String currency,
                String promotionCode, String promotionLabel,
                long walletAvailableMinor, boolean walletCovers, long shortfallMinor) {
}

record QuoteRequest(@NotNull UUID merchantId,
                    @NotEmpty @Size(max = 40) List<@Valid OrderLineRequest> lines,
                    @Size(max = 32) String promotionCode,
                    @Min(0) @Max(100_000) int tipCents) {
}

record TipRequest(@Min(1) @Max(100_000) int tipCents) {
}

/** A merchant's discount, on both the owner's editor and the customer's
 *  restaurant page. */
record PromotionDto(UUID id, String code, String label, String kind, int valueBps,
                    int amountCents, int minBasketCents, int maxDiscountCents,
                    int perUserLimit, OffsetDateTime startsAt, OffsetDateTime endsAt,
                    boolean active) {
}

record SavePromotionRequest(@Size(max = 32) String code,
                            @NotBlank @Size(max = 80) String label,
                            @NotBlank String kind,
                            @Min(0) @Max(10_000) int valueBps,
                            @Min(0) int amountCents,
                            @Min(0) int minBasketCents,
                            @Min(0) int maxDiscountCents,
                            @Min(0) @Max(100) int perUserLimit,
                            OffsetDateTime startsAt, OffsetDateTime endsAt) {
}

/**
 * A restaurant's money, on its owner's dashboard.
 *
 * <p>Lives on delivery's {@code /mine} surface rather than on the payments
 * module's, because only the module that owns a merchant can prove the caller
 * owns it — payments asking would be a dependency in the wrong direction
 * (ARCHITECTURE §10b: no admin-only mirror of the {@code /mine} endpoints).
 */
record MerchantWalletDto(long availableMinor, String currency, int commissionBps,
                         boolean payoutsConfigured, boolean payoutsReady,
                         String payoutsRequirement, long payoutMinMinor,
                         List<TransactionLineDto> recent) {
}

record TransactionLineDto(UUID id, long amountMinor, String kind, String memo,
                          OffsetDateTime createdAt) {
}

record PayoutRequestBody(@Min(1) long amountMinor) {
}

/** {@code status} is REQUESTED / SENT / FAILED — a payout that failed at the
 *  provider is reported, not hidden, and its debit has already been reversed. */
record PayoutDto(UUID id, long amountMinor, String currency, String status,
                 String failureReason) {
}

/** Wrapper so "no order in flight" is a 200 with {@code order: null}, not a 404. */
record ActiveOrderResponse(OrderDto order) {
}

record OrderLineRequest(@NotNull UUID menuItemId, @Min(1) @Max(50) int qty) {
}

/** {@code addressId} is a saved address of the caller's; the older
 *  {@code addressLabel} free-text form is still accepted so a client that
 *  predates saved addresses keeps working. One of the two is required. */
record PlaceOrderRequest(@NotNull UUID merchantId,
                         @NotEmpty @Size(max = 40) List<@Valid OrderLineRequest> lines,
                         UUID addressId,
                         @Size(max = 120) String addressLabel,
                         @Size(max = 280) String note,
                         /* A code, never an amount: what a discount is worth is
                          * read server-side from the promotion it names. */
                         @Size(max = 32) String promotionCode,
                         @Min(0) @Max(100_000) int tipCents) {
}

record RateOrderRequest(@Min(1) @Max(5) int rating) {
}
