package com.gojogo.partner.internal;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/**
 * An uploaded paper as its owner sees it. There is no URL here on purpose —
 * the applicant already has the file, and the object is private. A reviewer
 * gets a signed one, per view, from the admin surface.
 */
record PartnerDocumentDto(UUID id, String kind, String contentType, OffsetDateTime uploadedAt) {
}

/**
 * The applicant's own application.
 *
 * @param missingDocuments the required kinds not yet uploaded — what the app
 *                         renders as the checklist, computed here so the client
 *                         never has to know a kind's rules
 * @param canEdit          whether the form is open; false while under review
 *                         and once approved
 * @param refId            the restaurant an approval created, so the app can go
 *                         straight to the menu editor
 */
record PartnerAccountDto(UUID id, String kind, String status,
                         String businessName, UUID businessProfileId,
                         String category, String description, String logoUrl,
                         String contactName, String contactPhone, String contactEmail,
                         String country, String city, String addressLine,
                         Double latitude, Double longitude,
                         String reviewNote, UUID refId,
                         List<PartnerDocumentDto> documents,
                         List<String> requiredDocuments, List<String> missingDocuments,
                         boolean canEdit, boolean canSubmit,
                         OffsetDateTime submittedAt, OffsetDateTime reviewedAt,
                         OffsetDateTime createdAt) {
}

/** Wrapper so "you haven't applied" is a 200 with {@code account: null} rather
 *  than a 404 the client has to treat as success. */
record MyPartnerResponse(PartnerAccountDto account) {
}

record SavePartnerApplicationRequest(@NotBlank @Size(max = 16) String kind,
                                     @NotBlank @Size(max = 120) String businessName,
                                     UUID businessProfileId,
                                     @Size(max = 60) String category,
                                     @Size(max = 600) String description,
                                     @Size(max = 600) String logoUrl,
                                     @Size(max = 120) String contactName,
                                     @Size(max = 32) String contactPhone,
                                     @Size(max = 160) String contactEmail,
                                     @Size(max = 60) String country,
                                     @Size(max = 80) String city,
                                     @Size(max = 200) String addressLine,
                                     Double latitude, Double longitude) {
}

/**
 * An operator filing an application for a merchant (Phase 2e M2). The
 * application itself is the same object the merchant would have written — only
 * the "whose is it" part is new, and it is named rather than assumed.
 */
record AdminCreateApplicationRequest(UUID ownerProfileId,
                                     @Size(max = 60) String ownerHandle,
                                     @Valid @NotNull SavePartnerApplicationRequest application) {
}

/** Asks for somewhere to put one document. The key that comes back is what the
 *  client hands to {@link AttachDocumentRequest} once the bytes are in S3. */
record DocumentUploadRequest(@NotBlank @Size(max = 32) String kind,
                             @NotBlank @Size(max = 80) String contentType) {
}

record DocumentUploadResponse(String uploadUrl, String objectKey, String contentType,
                              long expiresSeconds) {
}

record AttachDocumentRequest(@NotBlank @Size(max = 32) String kind,
                             @NotBlank @Size(max = 400) String objectKey,
                             @Size(max = 80) String contentType) {
}

// MARK: Review (PartnerAdminController)

/** One row of the review queue, with signed links to the papers. */
record ReviewApplicationDto(PartnerAccountDto account, List<ReviewDocumentDto> documents) {
}

record ReviewDocumentDto(UUID id, String kind, String contentType, String url,
                         OffsetDateTime uploadedAt) {
}

record ReviewDecisionRequest(@Size(max = 400) String note) {
}

record RejectDecisionRequest(@NotNull @NotBlank @Size(max = 400) String note) {
}
