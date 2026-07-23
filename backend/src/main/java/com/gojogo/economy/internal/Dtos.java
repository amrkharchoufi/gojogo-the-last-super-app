package com.gojogo.economy.internal;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

record SellerSummary(UUID id, String name, String handle, String avatarUrl) {
}

record ListingResponse(UUID id, SellerSummary seller, String title, Long priceCents, String currency,
                       String category, String condition, String locationLabel, String description,
                       List<String> imageUrls, boolean saved, boolean isOwn,
                       int saveCount, OffsetDateTime createdAt) {
}

record ListingPageResponse(List<ListingResponse> listings, OffsetDateTime nextBefore) {
}

record CreateListingRequest(@NotBlank @Size(max = 140) String title,
                            @PositiveOrZero Long priceCents,
                            @Size(max = 3) String currency,
                            @Size(max = 60) String category,
                            @Size(max = 40) String condition,
                            @Size(max = 80) String locationLabel,
                            @Size(max = 5000) String description,
                            @Size(max = 10) List<@Size(max = 500) String> imageUrls) {
}
