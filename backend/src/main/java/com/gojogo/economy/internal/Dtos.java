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
                       String status, int saveCount, int viewCount,
                       OffsetDateTime createdAt, OffsetDateTime updatedAt) {
}

record ListingPageResponse(List<ListingResponse> listings, OffsetDateTime nextBefore) {
}

/** Where to continue a listing conversation, plus the opener the buyer can send
 *  as-is. Nothing is posted on the buyer's behalf — the client prefills it. */
record ListingChatResponse(UUID conversationId, UUID sellerId, String suggestedMessage) {
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

/** A full replacement of the seller's own listing — the edit form posts every
 *  field back, so an omitted one means "clear it", not "keep it". */
record UpdateListingRequest(@NotBlank @Size(max = 140) String title,
                            @PositiveOrZero Long priceCents,
                            @Size(max = 3) String currency,
                            @Size(max = 60) String category,
                            @Size(max = 40) String condition,
                            @Size(max = 80) String locationLabel,
                            @Size(max = 5000) String description,
                            @Size(max = 10) List<@Size(max = 500) String> imageUrls) {
}

/** ACTIVE / PAUSED / SOLD — the seller taking a listing down or marking it sold. */
record UpdateListingStatusRequest(@NotBlank String status) {
}

/** The seller's own numbers, for the top of "Your listings". Computed server
 *  side so the totals cover every listing, not just the page in hand. */
record SellerStatsResponse(int total, int active, int paused, int sold,
                           int saves, int views) {
}
