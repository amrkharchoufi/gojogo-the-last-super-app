package com.gojogo.travel.internal;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

record QuoteRequest(@NotNull @DecimalMin("-90") @DecimalMax("90") Double pickupLatitude,
                    @NotNull @DecimalMin("-180") @DecimalMax("180") Double pickupLongitude,
                    @NotNull @DecimalMin("-90") @DecimalMax("90") Double dropoffLatitude,
                    @NotNull @DecimalMin("-180") @DecimalMax("180") Double dropoffLongitude) {
}

/**
 * Every category priced at once, so the picker shows real numbers rather than
 * making somebody tap through six screens to compare them.
 */
record QuoteResponse(long distanceMetres, long durationSeconds, String currency,
                     List<QuotedCategory> categories) {
}

/** @param minimumMinor the floor a negotiation may not go under — shown, because
 *                      "make me an offer" needs a stated bottom */
record QuotedCategory(String category, long suggestedFareMinor, long minimumMinor) {
}

/** @param offeredFareMinor what the rider puts on the table, or null to take the
 *                          suggestion. This is what drivers are answering */
record RequestRideRequest(@NotBlank @Size(max = 16) String category,
                          @NotNull @DecimalMin("-90") @DecimalMax("90") Double pickupLatitude,
                          @NotNull @DecimalMin("-180") @DecimalMax("180") Double pickupLongitude,
                          @Size(max = 200) String pickupLabel,
                          @NotNull @DecimalMin("-90") @DecimalMax("90") Double dropoffLatitude,
                          @NotNull @DecimalMin("-180") @DecimalMax("180") Double dropoffLongitude,
                          @Size(max = 200) String dropoffLabel,
                          @Size(max = 280) String note,
                          Long offeredFareMinor) {
}

record OfferAmountRequest(@NotNull @Min(1) Long amountMinor) {
}

record CancelRideRequest(@Size(max = 280) String reason) {
}

record RateRideRequest(@NotNull @Min(1) @Max(5) Integer stars) {
}

/**
 * One ride, from whichever side is looking at it.
 *
 * @param otherPartyName    the driver, to a rider; the rider, to a driver
 * @param driverLatitude    where the car is right now, while the trip is live —
 *                          read from dispatch per request rather than stored, so
 *                          it can never be a stale copy
 * @param myRating          what this viewer gave the other side
 * @param theirRating       what the other side gave them, and <b>null until both
 *                          are in</b>: reading a one-star before writing your own
 *                          turns a rating into a reply
 * @param offers            live counteroffers. A rider sees all of them; a driver
 *                          sees only their own, because three drivers' prices are
 *                          three private conversations
 * @param tokenCost         what this trip cost the driver in tokens, and
 *                          <b>null to the rider</b> — the price list is public,
 *                          but what the driver paid for the job is not a line on
 *                          a passenger's receipt
 * @param vehicleVerified   passengers have confirmed this car is what it claims
 *                          to be (Phase 3 M5). A snapshot taken at CONFIRMED, so
 *                          an old receipt does not retroactively claim a badge
 *                          the car did not have at the time
 * @param sosAt             when an alarm was raised on this trip, or null. Shown
 *                          to <b>both</b> parties: a driver whose passenger has
 *                          pressed it needs to know, and hiding it would be a
 *                          product pretending nothing happened
 */
record RideDto(UUID id, String state, String category,
               String pickupLabel, double pickupLatitude, double pickupLongitude,
               String dropoffLabel, double dropoffLatitude, double dropoffLongitude,
               String note, int distanceMetres, int durationSeconds,
               long suggestedFareMinor, long offeredFareMinor, Long agreedFareMinor,
               String currency, long cancelFeeMinor, Integer tokenCost,
               UUID otherPartyId, String otherPartyName, String otherPartyAvatarUrl,
               String vehicleLabel, String vehiclePlate, boolean vehicleVerified,
               Double driverLatitude, Double driverLongitude, OffsetDateTime driverPositionAt,
               UUID conversationId, List<RideOfferDto> offers,
               Integer myRating, Integer theirRating, OffsetDateTime sosAt,
               OffsetDateTime expiresAt, OffsetDateTime requestedAt,
               OffsetDateTime confirmedAt, OffsetDateTime startedAt,
               OffsetDateTime completedAt, String cancelReason) {
}

// MARK: Safety (Phase 3 M5, SPECS §10)

/**
 * A public link to a live trip.
 *
 * @param message  the whole thing, already written, for the phone's own share
 *                 sheet. Composed here rather than in the app because the
 *                 wording of a safety message is not a place for six clients to
 *                 each have their own idea
 * @param viewCount whether anybody actually opened it, which is the one question
 *                  a person who shared a trip asks
 */
record ShareTripDto(String url, OffsetDateTime expiresAt, int viewCount, String message) {
}

/**
 * What comes back from pressing SOS.
 *
 * <p><strong>The server does not call anybody.</strong> It returns the number
 * for the phone to dial, because a backend placing an emergency call on
 * somebody's behalf is a claim about integration with emergency services that
 * this system has no right to make (SPECS §10 — "no PSAP integration claimed").
 *
 * @param contacts       every emergency contact, so the app can open the message
 *                       composer for the ones who are only a phone number
 * @param notifiedCount  how many were reached by push, which is the honest
 *                       number: it is the contacts who are also GojoGo accounts,
 *                       and usually fewer than the list
 */
record SosDto(String emergencyNumber, String shareUrl, String message,
              List<com.gojogo.profile.EmergencyContactDto> contacts, int notifiedCount,
              OffsetDateTime raisedAt) {
}

/** One flagged trip, as an operator sees it. */
record SosRideDto(UUID rideId, String state, OffsetDateTime sosAt, UUID raisedBy,
                  UUID riderId, UUID driverUserId, String driverName,
                  String pickupLabel, String dropoffLabel,
                  String vehicleLabel, String vehiclePlate, OffsetDateTime requestedAt) {
}

/**
 * What a ride costs its driver, one band (Phase 3 M4).
 *
 * @param upToMetres trips of this length or shorter cost {@code tokens}; the
 *                   longest band per category is the catch-all
 */
record TokenPriceDto(String category, int upToMetres, int tokens) {
}

/**
 * The driver's token standing — the screen that explains why work is or isn't
 * arriving.
 *
 * <p>{@code refusal} is the point of this endpoint. Dispatch stops offering
 * silently and correctly when a driver cannot pay, so without a sentence here a
 * driver sits online watching nothing happen and concludes the app is broken.
 *
 * @param balance    whole tokens held
 * @param cheapest   the least any trip could cost — zero when the model is off
 * @param canWork    whether anything at all could be offered right now
 * @param refusal    null when they can work, otherwise a sentence to show them
 */
record MyRideTokensDto(long balance, int cheapest, boolean canWork, String refusal,
                       List<TokenPriceDto> prices) {
}

/** @param party RIDER | DRIVER — which decides who may accept it */
record RideOfferDto(UUID id, UUID rideId, String party, long amountMinor, int round,
                    String state, UUID driverId, String driverName, String driverAvatarUrl,
                    OffsetDateTime expiresAt, OffsetDateTime createdAt) {
}

/** Wrapper so "no ride in progress" is a 200 with {@code ride: null} rather than
 *  a 404 the client has to treat as success. */
record MyRideResponse(RideDto ride) {
}
