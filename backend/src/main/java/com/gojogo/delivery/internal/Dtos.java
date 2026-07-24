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
                String currency, String addressLabel, OrderAddressDto address, String note,
                Integer rating,
                OffsetDateTime placedAt, OffsetDateTime statusChangedAt, OffsetDateTime etaAt) {
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
                         @Size(max = 280) String note) {
}

record RateOrderRequest(@Min(1) @Max(5) int rating) {
}
