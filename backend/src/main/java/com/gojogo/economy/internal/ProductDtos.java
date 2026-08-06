package com.gojogo.economy.internal;

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

/**
 * The wire shapes of the product half of economy. One file, records only —
 * the same layout as {@code Dtos.java} next door, split out so the listing
 * shapes and the product shapes don't shuffle together.
 */
final class ProductDtos {

    private ProductDtos() {
    }

    // MARK: Seller console

    record SellerResponse(UUID id, String displayName, String logoUrl,
                          int shippingFlatCents, int freeShippingOverCents, int taxBps,
                          boolean suspended, String currency) {
    }

    record UpdateSellerRequest(@NotBlank @Size(max = 120) String displayName,
                               String logoUrl,
                               @Min(0) int shippingFlatCents,
                               @Min(0) int freeShippingOverCents,
                               @Min(0) @Max(10_000) int taxBps) {
    }

    // MARK: Catalog

    record VariantRequest(UUID id,
                          @Size(max = 64) String sku,
                          @NotBlank @Size(max = 120) String label,
                          @Min(0) long priceCents,
                          @Min(0) int stock,
                          boolean active) {
    }

    record CreateProductRequest(@NotBlank @Size(max = 140) String name,
                                @Size(max = 8000) String description,
                                @Size(max = 60) String category,
                                @Size(max = 80) String brand,
                                @Size(max = 8000) String specs,
                                List<String> imageUrls,
                                @NotEmpty @Valid List<VariantRequest> variants,
                                @Size(max = 16) String kind) {
    }

    record VariantResponse(UUID id, String sku, String label, long priceCents,
                           int stock, boolean active) {
    }

    record ProductResponse(UUID id, UUID sellerId, String sellerName, String sellerLogoUrl,
                           String name, String description, String category, String brand,
                           String kind, String specs, List<String> imageUrls,
                           List<VariantResponse> variants, boolean active,
                           Double averageRating, int ratingCount,
                           OffsetDateTime createdAt, OffsetDateTime updatedAt) {
    }

    record ProductPageResponse(List<ProductResponse> items, OffsetDateTime nextBefore) {
    }

    // MARK: Promotions

    record CreatePromotionRequest(@Size(max = 40) String code,
                                  @Size(max = 120) String label,
                                  @NotBlank String kind,
                                  @Min(0) @Max(10_000) int valueBps,
                                  @Min(0) int amountCents,
                                  @Min(0) int minBasketCents,
                                  @Min(0) int maxDiscountCents,
                                  @Min(0) int perUserLimit,
                                  OffsetDateTime startsAt,
                                  OffsetDateTime endsAt) {
    }

    record PromotionResponse(UUID id, String code, String label, String kind, int valueBps,
                             int amountCents, int minBasketCents, int maxDiscountCents,
                             int perUserLimit, boolean active,
                             OffsetDateTime startsAt, OffsetDateTime endsAt) {
    }

    // MARK: Checkout + orders

    record CheckoutLine(@NotNull UUID variantId, @Min(1) @Max(99) int quantity) {
    }

    record CheckoutRequest(@NotEmpty @Valid List<CheckoutLine> lines,
                           @Size(max = 500) String shipTo,
                           @Size(max = 40) String promotionCode) {
    }

    record OrderLineResponse(UUID productId, UUID variantId, String productName,
                             String variantLabel, long unitPriceCents, int quantity,
                             long lineTotalCents) {
    }

    record OrderResponse(UUID id, UUID sellerId, String sellerName, String status,
                         int subtotalCents, int discountCents, int shippingCents,
                         int taxCents, int totalCents, String currency,
                         String promotionLabel, String shipTo, String trackingNote,
                         List<OrderLineResponse> lines,
                         OffsetDateTime placedAt, OffsetDateTime shippedAt,
                         OffsetDateTime completedAt, OffsetDateTime cancelledAt) {
    }

    record ShipRequest(@Size(max = 500) String trackingNote) {
    }

    // MARK: Reviews

    record CreateReviewRequest(@NotNull UUID orderId,
                               @Min(1) @Max(5) int rating,
                               @Size(max = 4000) String body,
                               List<String> photoUrls) {
    }

    record ReviewResponse(UUID id, UUID productId, UUID authorId, String authorName,
                          String authorAvatarUrl, int rating, String body,
                          List<String> photoUrls, String replyBody,
                          OffsetDateTime repliedAt, OffsetDateTime createdAt) {
    }

    record ReplyRequest(@NotBlank @Size(max = 2000) String body) {
    }

    // MARK: Special catalogs (Phase 5 M2)

    record AttachDigitalAssetRequest(@NotBlank String objectKey,
                                     @Size(max = 140) String fileName,
                                     @Size(max = 100) String contentType,
                                     @Size(max = 16) String entitlementKind) {
    }

    record EntitlementResponse(UUID id, UUID productId, String productName, String kind,
                               String licenseKey, String fileName,
                               OffsetDateTime expiresAt, OffsetDateTime createdAt) {
    }

    record DownloadResponse(String url) {
    }

    record AcceptTransferRequest(@Min(1) long priceCents) {
    }

    record CancelTransferRequest(@Size(max = 500) String note) {
    }

    record AttachTransferDocumentRequest(@NotBlank String objectKey,
                                         @Size(max = 80) String label) {
    }

    record TransferDocumentResponse(UUID id, String label, String readUrl,
                                    OffsetDateTime uploadedAt) {
    }

    record TransferResponse(UUID id, UUID listingId, String listingTitle, String vinSerial,
                            UUID sellerId, UUID buyerId, String state, Long priceCents,
                            String currency, boolean flaggedManual,
                            OffsetDateTime createdAt, OffsetDateTime acceptedAt,
                            OffsetDateTime paidAt, OffsetDateTime docsConfirmedAt,
                            OffsetDateTime transferredAt, OffsetDateTime releasedAt,
                            OffsetDateTime cancelledAt, String cancelNote,
                            // How many papers are attached. The app had no way to
                            // tell an upload that worked from one that didn't, which
                            // is how a silently-dropped upload went unnoticed.
                            long documentCount) {
    }
}
