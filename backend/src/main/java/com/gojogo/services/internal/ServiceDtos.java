package com.gojogo.services.internal;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/** The wire shapes of the services vertical. Records only, one file. */
final class ServiceDtos {

    private ServiceDtos() {
    }

    // MARK: Provider

    record ProviderResponse(UUID id, String displayName, String logoUrl, String bio,
                            String qualifications, String serviceAreas, String languages,
                            String timezone, List<String> portfolioUrls, boolean suspended,
                            OffsetDateTime createdAt) {
    }

    record UpdateProviderRequest(@NotBlank @Size(max = 120) String displayName,
                                 String logoUrl,
                                 @Size(max = 4000) String bio,
                                 @Size(max = 4000) String qualifications,
                                 @Size(max = 500) String serviceAreas,
                                 @Size(max = 500) String languages,
                                 @Size(max = 50) String timezone,
                                 @Size(max = 12) List<@Size(max = 500) String> portfolioUrls) {
    }

    record ProviderDocumentResponse(UUID id, String label, String readUrl,
                                    OffsetDateTime uploadedAt) {
    }

    record AttachProviderDocumentRequest(@NotBlank String objectKey,
                                         @Size(max = 80) String label) {
    }

    // MARK: Catalog

    record ServiceRequest(@NotBlank @Size(max = 140) String name,
                          @Size(max = 8000) String description,
                          @Size(max = 60) String category,
                          @Min(5) @Max(1440) int durationMinutes,
                          @Min(0) Long priceCents,
                          @Size(max = 16) String locationKind,
                          @Size(max = 4000) String requirements) {
    }

    record ServiceResponse(UUID id, UUID providerId, String providerName, String providerLogoUrl,
                           String name, String description, String category,
                           int durationMinutes, Long priceCents, boolean priceOnQuote,
                           String currency, String locationKind, String requirements,
                           boolean active, Double averageRating, int ratingCount,
                           OffsetDateTime createdAt) {
    }

    record ServicePageResponse(List<ServiceResponse> items, OffsetDateTime nextBefore) {
    }

    // MARK: Availability

    record AvailabilityRuleRequest(@Min(1) @Max(7) int dayOfWeek,
                                   @Min(0) @Max(1439) int startMinute,
                                   @Min(1) @Max(1440) int endMinute) {
    }

    record AvailabilityRuleResponse(UUID id, int dayOfWeek, int startMinute, int endMinute) {
    }

    record ReplaceAvailabilityRequest(@NotNull List<AvailabilityRuleRequest> rules) {
    }

    record ExceptionRequest(@NotNull LocalDate onDate) {
    }

    record SlotsResponse(UUID serviceId, int durationMinutes, String timezone,
                         List<OffsetDateTime> slots) {
    }

    // MARK: Bookings

    record BookingRequestBody(@NotNull UUID serviceId,
                              @NotNull OffsetDateTime startsAt,
                              @Size(max = 2000) String note) {
    }

    record QuoteRequest(@Min(1) long priceCents) {
    }

    record BookingResponse(UUID id, UUID serviceId, String serviceName, UUID providerId,
                           String providerName, UUID customerId, String status,
                           OffsetDateTime startsAt, int durationMinutes, Long priceCents,
                           String currency, String paymentStatus, String note,
                           UUID conversationId, long cancellationFeeCents,
                           OffsetDateTime requestedAt, OffsetDateTime quotedAt,
                           OffsetDateTime confirmedAt, OffsetDateTime completedAt,
                           OffsetDateTime cancelledAt) {
    }

    // MARK: Reviews

    record CreateServiceReviewRequest(@NotNull UUID bookingId,
                                      @Min(1) @Max(5) int rating,
                                      @Size(max = 4000) String body) {
    }

    record ServiceReviewResponse(UUID id, UUID serviceId, UUID authorId, String authorName,
                                 String authorAvatarUrl, int rating, String body,
                                 String replyBody, OffsetDateTime repliedAt,
                                 OffsetDateTime createdAt) {
    }

    record ServiceReplyRequest(@NotBlank @Size(max = 2000) String body) {
    }
}
