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
 * @param identityRequired whether an IDV vendor is answering the identity half.
 *                         False on an environment with no vendor configured,
 *                         where identity is still proved by uploading an ID —
 *                         which is why {@code requiredDocuments} above changes
 *                         shape with it rather than being a fixed list
 * @param identityStatus   where that check stands, as a
 *                         {@code com.gojogo.kyc.IdentityStatus} name
 * @param identityReason   why it was refused, in words meant for the applicant
 * @param canEdit          whether the form is open; false while under review
 *                         and once approved
 * @param canSubmit        everything the server would check on submit, answered
 *                         in advance — identity included, so the app never
 *                         offers a button that is going to 400
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
                         boolean identityRequired, String identityStatus, String identityReason,
                         StakeStatus stake, List<VehicleDto> vehicles,
                         boolean vehicleRequired, String submitBlocker,
                         boolean canEdit, boolean canSubmit,
                         OffsetDateTime submittedAt, OffsetDateTime reviewedAt,
                         OffsetDateTime createdAt) {
}

/** Wrapper so "you haven't applied" is a 200 with {@code account: null} rather
 *  than a 404 the client has to treat as success. */
record MyPartnerResponse(PartnerAccountDto account) {
}

// MARK: Vehicles + the stake (Phase 3 M2)

/**
 * One vehicle, as its owner and a reviewer both see it.
 *
 * @param papersExpired computed here rather than left to the client to work out
 *                      from two dates — an app that got that arithmetic wrong
 *                      would tell somebody they can drive when they cannot
 * @param missingDocuments what still has to be uploaded, so the checklist is the
 *                      server's rule rendered rather than a second copy of it
 */
record VehicleDto(UUID id, String category, String make, String model, Integer year,
                  String color, String plate, String region,
                  String state, boolean active,
                  String registrationExpiresOn, String insuranceExpiresOn,
                  boolean papersExpired, String reviewNote,
                  List<String> photoUrls, List<PartnerDocumentDto> documents,
                  List<String> missingDocuments, OffsetDateTime createdAt) {
}

/** Dates arrive as {@code yyyy-MM-dd} strings, because a vehicle's insurance
 *  expires on a day in a timezone nobody recorded. */
record SaveVehicleRequest(@NotBlank @Size(max = 16) String category,
                          @Size(max = 60) String make,
                          @Size(max = 60) String model,
                          Integer year,
                          @Size(max = 30) String color,
                          @Size(max = 20) String plate,
                          @Size(max = 60) String region,
                          @Size(max = 10) String registrationExpiresOn,
                          @Size(max = 10) String insuranceExpiresOn,
                          List<String> photoUrls) {
}

/**
 * The stake page, answered by the server so the app never has to know a price.
 *
 * @param shortfallMinor what is still needed in the wallet — which is what turns
 *                       "you can't afford this" into a top-up button for the
 *                       right amount, rather than a dead end
 * @param remainingMinor what is still locked after the ID check took its fee
 */
record StakeStatus(boolean required, long requiredMinor, long paidMinor,
                   long kycFeeMinor, long remainingMinor,
                   OffsetDateTime paidAt, OffsetDateTime releasedAt,
                   String currency, long walletAvailableMinor, long shortfallMinor) {
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
record ReviewApplicationDto(PartnerAccountDto account, List<ReviewDocumentDto> documents,
                            List<ReviewVehicleDto> vehicles) {
}

/** A vehicle as a reviewer sees it: the same object, plus links to its papers. */
record ReviewVehicleDto(VehicleDto vehicle, List<ReviewDocumentDto> documents) {
}

/** @param approved false flags it, which is not a rejection — a re-upload
 *                  puts it back in the queue */
record VehicleReviewRequest(boolean approved, @Size(max = 400) String note) {
}

record ReviewDocumentDto(UUID id, String kind, String contentType, String url,
                         OffsetDateTime uploadedAt) {
}

record ReviewDecisionRequest(@Size(max = 400) String note) {
}

record RejectDecisionRequest(@NotNull @NotBlank @Size(max = 400) String note) {
}
