package com.gojogo.delivery.internal;

import com.gojogo.storefront.StorefrontBlock;
import com.gojogo.storefront.StorefrontDocument;
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

/**
 * A restaurant. {@code menu} is empty in browse results and filled on detail,
 * and so is {@code storefront} — the owner's arrangement of the page above the
 * menu (SPECS §9), which is always present and empty (version 0) for a
 * restaurant nobody has arranged, so the app has one code path either way.
 */
record MerchantDto(UUID id, String name, String cuisine, double rating, int reviewCount,
                   int etaMinutes, int deliveryFeeCents, String imageUrl, String promo,
                   List<String> tags, List<String> categories,
                   double latitude, double longitude, List<MenuSectionDto> menu,
                   StorefrontDocument storefront,
                   /* Collection (Phase 4 M4). {@code pickupEnabled} is what the
                    * app draws the "Collect in store" choice from at all;
                    * {@code pickupEtaMinutes} is what that choice promises, and
                    * is the merchant's own pickup time or their delivery ETA
                    * when they have not set one. A client that predates these
                    * fields simply never offers collection, which is the right
                    * behaviour for a build that could not price it. */
                   boolean pickupEnabled, int pickupEtaMinutes, String pickupAddress,
                   /* Opening hours (Phase 4 M6). {@code openNow} is the server's
                    * own answer, read in the restaurant's timezone — the app
                    * must not re-derive it, because it does not know their zone
                    * and a card that says "open" over a kitchen that will refuse
                    * the checkout is worse than one that says "closed".
                    * {@code openingHours} is the raw schedule, for a page that
                    * wants to draw the week. */
                   boolean openNow, String openingHours) {
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
                     boolean open, boolean suspended,
                     /* Collection (Phase 4 M4). {@code pickupPrepMinutes} is
                      * null for "the same as delivery" — the owner's editor
                      * shows a placeholder rather than a number nobody chose. */
                     boolean pickupEnabled, Integer pickupPrepMinutes, String pickupAddress,
                     /* Their own schedule and zone (Phase 4 M6). Blank hours is
                      * always-open, which is what every restaurant was before
                      * this — an owner who never opens the editor keeps trading
                      * exactly as they did. */
                     String openingHours, String timezone, boolean openNow,
                     List<MyMenuSectionDto> menu) {
}

/** The pickup fields are optional on the wire: a client that predates Phase 4
 *  M4 sends none of them, and a save from it must not silently switch
 *  collection off for a restaurant that had it on. Absent means unchanged; the
 *  service reads them that way. */
record UpdateMerchantRequest(@NotBlank @Size(max = 120) String name,
                             @NotBlank @Size(max = 80) String cuisine,
                             @Size(max = 600) String imageUrl,
                             @Size(max = 60) String promo,
                             @Min(5) @Max(180) int etaMinutes,
                             @Min(0) @Max(100_000) int deliveryFeeCents,
                             Double latitude, Double longitude,
                             @Size(max = 8) List<@Size(max = 40) String> categories,
                             @Size(max = 8) List<@Size(max = 40) String> tags,
                             Boolean pickupEnabled,
                             @Min(1) @Max(1440) Integer pickupPrepMinutes,
                             @Size(max = 200) String pickupAddress,
                             /* Absent means unchanged, like the pickup fields
                              * above and for the same reason: a save from a
                              * client that predates Phase 4 M6 must not wipe a
                              * schedule somebody set. */
                             @Size(max = 400) String openingHours,
                             @Size(max = 64) String timezone) {
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

/**
 * A whole storefront, replacing whatever was there. A null or absent list is an
 * empty page rather than an error — clearing a storefront should not require
 * knowing a special verb.
 */
record SaveStorefrontRequest(@Size(max = 100) List<StorefrontBlock> blocks) {
}

record OrderMerchantDto(UUID id, String name, String imageUrl, double latitude, double longitude) {
}

/**
 * Whoever is bringing the food. Since Phase 4 M1 this is a real person out of
 * the dispatch registry rather than one of four hardcoded names, which is why
 * it grew a position: a live one, reported by their phone, and present only
 * while they are actually carrying this order.
 */
record CourierDto(String name, String vehicle, double rating, int deliveries,
                  Double latitude, Double longitude, OffsetDateTime positionAt) {
}

record OrderLineDto(UUID menuItemId, String name, int unitPriceCents, int qty) {
}

/**
 * One merchant's slice of an order, as the customer sees it (Phase 4 M3).
 *
 * <p>{@code status} is the sub-order's own vocabulary — CONFIRMED / PREPARING /
 * COLLECTED / DELIVERED / CANCELLED — beside the parent's six words, because
 * "Dar Zellij is cooking, Sweet Corner turned theirs down" is per-kitchen news
 * the parent status cannot carry. {@code cancellable} says whether this slice
 * alone can still be cancelled: true exactly while its merchant hasn't
 * answered, which is the SPECS §5 rule, computed here so the client never
 * re-derives it.
 */
record SubOrderDto(UUID id, UUID merchantId, String merchantName, String merchantImageUrl,
                   String status, boolean cancellable, List<OrderLineDto> lines,
                   int subtotalCents, int deliveryFeeCents, int discountCents,
                   String promotionCode, int prepMinutes, OffsetDateTime readyAt,
                   OffsetDateTime collectedAt, String cancelReason,
                   /* Collection (Phase 4 M4), and empty on every delivery
                    * order. {@code collectionCode} is the same six digits M2
                    * minted and M3 put on the slice — returned to the customer
                    * here, because for a pickup it is the *merchant* who types
                    * it. One rule underneath both milestones: the code is shown
                    * to the party that does not type it. {@code readyToCollect}
                    * is the kitchen's own word that the food is on the counter,
                    * which an estimate cannot say. */
                   String collectionCode, boolean readyToCollect,
                   String pickupAddress, Double pickupLatitude, Double pickupLongitude,
                   OffsetDateTime readyMarkedAt) {
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
 * are derived server-side, so two devices watching the same order agree and a
 * reinstall picks the countdown back up.
 *
 * <p>Three fields arrived with real couriers (Phase 4 M1) and all three exist to
 * say something the simulation never had to. {@code courierSearch} is NONE /
 * SEARCHING / ASSIGNED / FAILED — the only way a customer learns that the
 * restaurant is cooking but nobody has taken the delivery yet, which is not a
 * stage of an order and so is deliberately not a seventh {@code status}.
 * {@code readyAt} is when the kitchen says the food will be done, i.e. the first
 * estimate in this vertical's history that a person gave. {@code cancelReason}
 * is why it ended, because "cancelled" alone leaves a customer wondering whether
 * they did it.
 *
 * <p>Four more arrived with handoff integrity (Phase 4 M2), and between them
 * they are the customer's whole half of it. {@code deliveryPin} is the number
 * they read out at the door — <b>returned here and nowhere else</b>, and blank
 * once the order is finished or the mode is not PIN, because a PIN that outlives
 * its handoff is a PIN sitting in a screenshot. {@code proofPhotoUrl} is a
 * short-lived signed GET minted per read rather than a stored link; the object
 * key behind it never leaves the server. {@code handoffMode} is what the control
 * on their tracking card is currently set to, and {@code conversationId} is the
 * thread with whoever is carrying the food.
 */
record OrderDto(UUID id, OrderMerchantDto merchant, String status, int etaMinutes,
                /* DELIVERY | PICKUP (Phase 4 M4). The one field a client has to
                 * read before rendering anything else about fulfilment: a
                 * PICKUP order has no courier and never visits two of the six
                 * statuses, so a screen that draws "looking for a courier" from
                 * courierSearch = NONE would be describing a search nobody
                 * opened. Absent on a client that predates it, which only ever
                 * receives DELIVERY orders — it cannot place any other kind. */
                String fulfilmentKind,
                double courierProgress, CourierDto courier,
                String courierSearch, String cancelReason, OffsetDateTime readyAt,
                List<OrderLineDto> lines,
                /* One per merchant since Phase 4 M3. The flat fields above stay
                 * populated — merchant is the first slice's, lines are all of
                 * them — so a client that predates sub-orders keeps rendering
                 * the common single-merchant case exactly as before. */
                List<SubOrderDto> subOrders,
                int subtotalCents, int deliveryFeeCents, int serviceFeeCents, int totalCents,
                int discountCents, int tipCents, String promotionCode,
                String paymentStatus,
                String currency, String addressLabel, OrderAddressDto address, String note,
                /* Who is at the door, when that is not the person paying
                 * (Phase 4 M6). Blank on the overwhelming majority of orders.
                 * The phone is returned here — to the customer who typed it,
                 * on their own order — and nowhere else: not on the courier's
                 * job, not on a share link. */
                String recipientName, String recipientPhone,
                Integer rating,
                /* What they thought of the courier (Phase 4 M6), or null while
                 * they haven't said. Beside the order rating rather than
                 * replacing it, because the two are answers to different
                 * questions — that separation is why this took five milestones
                 * rather than being folded into `rating` on day one. */
                Integer courierRating,
                String handoffMode, String deliveryPin, String proofPhotoUrl,
                UUID conversationId,
                /* Scheduling (Phase 4 M5). {@code scheduledFor} is null on an
                 * ordinary order and is what a client shows instead of a
                 * countdown — a "4320 min" ETA is arithmetic, not information.
                 * {@code changeable} is the server's own answer to "can this
                 * still be edited", computed rather than re-derived on the
                 * client for the same reason {@code SubOrderDto.cancellable}
                 * is: a rule with two definitions drifts. {@code queuedAt} is
                 * when the kitchens were told, which is the moment it stopped
                 * being editable. */
                OffsetDateTime scheduledFor, boolean changeable, OffsetDateTime queuedAt,
                OffsetDateTime placedAt, OffsetDateTime statusChangedAt, OffsetDateTime etaAt) {
}

/** How the customer wants the food handed over — {@code PIN}, {@code PHOTO} or
 *  {@code CONFIRM}. An unrecognised word is the configured default rather than a
 *  400: this is a one-tap control, and a 400 on it is a control that looks
 *  broken. */
record HandoffModeRequest(@Size(max = 16) String mode) {
}

// MARK: The kitchen's queue (OrderFulfilmentService)

/**
 * One kitchen's slice of an order, as that restaurant sees it. Since Phase 4
 * M3 {@code id} is the <b>sub-order</b> id — accept, reject and ready act on
 * it — and the DTO deliberately says nothing about the other merchants on the
 * order: what another kitchen is cooking is not this one's business.
 *
 * <p>{@code status} keeps the order's six-word vocabulary, derived from the
 * slice plus the parent (a COLLECTED slice reads as DELIVERING — "the courier
 * has your bag"), so the deployed kitchen screen renders a multi-merchant
 * order without having been taught a new word.
 *
 * @param earningsMinor what this slice is worth to them after commission, which
 *                      is the number an owner actually reads
 * @param courierSearch whether anybody is coming for it — a kitchen with food
 *                      ready and no courier needs to know that before the food
 *                      does
 * @param pickupCode    the six digits the courier has to type at <em>this</em>
 *                      counter. On the kitchen's DTO and on no other, and the
 *                      delivery PIN is on neither: a restaurant has no business
 *                      knowing the number that confirms the food reached
 *                      somebody's door
 */
record MerchantOrderDto(UUID id, String status, List<OrderLineDto> lines,
                        int subtotalCents, int discountCents, String currency,
                        long earningsMinor, String note, String addressLabel,
                        String courierName, String courierSearch, int prepMinutes,
                        String cancelReason, String pickupCode,
                        /* DELIVERY | PICKUP (Phase 4 M4). What decides which
                         * screen the kitchen gets: a courier coming for it, or
                         * a customer at the counter with a code to be typed in.
                         * On a PICKUP slice {@code pickupCode} above is
                         * deliberately <b>blank</b> — the kitchen types that
                         * code, so a kitchen that could read it could hand the
                         * food to nobody and settle the order. */
                        String fulfilmentKind, boolean readyMarked,
                        /* When the customer asked for it (Phase 4 M5), or null
                         * for an ordinary order. The one thing a kitchen must
                         * be told about a scheduled order: accepting at 18:15
                         * with a prep of twenty minutes does not mean the food
                         * is wanted at 18:35, and a screen that did not say so
                         * would have somebody cooking an eight o'clock dinner
                         * two hours early. The prep estimate keeps its meaning
                         * — how long they need, not when they start. */
                        OffsetDateTime scheduledFor,
                        OffsetDateTime placedAt, OffsetDateTime acceptedAt,
                        OffsetDateTime readyAt, OffsetDateTime statusChangedAt) {
}

/** A prep estimate, or null for the configured default. Not required, because
 *  an accept that can fail validation is an accept somebody in a kitchen does
 *  not make. */
record AcceptOrderRequest(@Min(1) @Max(1440) Integer prepMinutes) {
}

record RejectOrderRequest(@Size(max = 240) String reason) {
}

/** The code the customer is holding up, as the kitchen typed it. Optional, for
 *  the same reason the courier's is: "I typed nothing" is an outcome this
 *  endpoint has an answer for rather than a validation failure. */
record CollectOrderRequest(@Size(max = 16) String code) {
}

/**
 * The answer to a collection attempt — a 200 whether or not the code matched,
 * exactly as the courier's two handoff verbs are, and for the same reason: a
 * mistyped digit at a counter is not a bad request, and an error banner in
 * front of somebody holding a paid-for bag of food is the wrong thing to draw.
 *
 * @param attemptsLeft always <b>-1</b>, meaning "not counted". The asymmetry M2
 *                     drew is about who is standing there: at a counter the
 *                     other party is present, so the code is a check rather than
 *                     a gate, and locking a kitchen out of handing over food
 *                     they have already made is the worse failure by far
 * @param order        the slice as it now stands, present on a refusal too — a
 *                     wrong code must not blank the screen the kitchen is
 *                     working from
 */
record CollectionResultDto(boolean accepted, String message, int attemptsLeft,
                           MerchantOrderDto order) {
}

// MARK: The courier's screen

/**
 * A delivery from the other end. Two addresses, what is in the bag and what it
 * pays — and deliberately nothing else about the customer: a courier needs to
 * find a door, not to know who lives behind it.
 *
 * <p><b>Neither code is on it, and that is the whole design.</b> The pickup code
 * is on the kitchen's screen and the delivery PIN on the customer's; a courier
 * who could read either from their own job could collect food they are not
 * standing in front of and confirm a delivery they have not made.
 *
 * <p><b>The handoff <em>mode</em> is a different thing and is on it, deliberately.</b>
 * The line above is about the two secrets, and it is easy to over-apply — the
 * first build of the courier screen withheld the mode as well, which made a
 * contactless order dead-end: the app offered a PIN field for a PIN nobody was
 * ever going to read out, and the only way through was a refusal message. That
 * is the smaller half of the problem. The larger half is that "leave it at the
 * door" is <em>an instruction the customer gave</em>, in the same category as
 * {@code note}, and an app that does not relay it has a courier knocking on the
 * door of somebody who asked them not to. Knowing the mode discloses nothing:
 * it is the shape of the check, not the answer to it.
 *
 * @param payMinor the delivery fee plus whatever was tipped at checkout. The
 *                 number a courier decides by, and as of this milestone a number
 *                 that actually reaches them
 * @param handoffMode PIN | PHOTO | CONFIRM — how this customer wants it handed
 *                 over, so the courier's screen can lead with the right thing
 *                 and the doorstep is not a surprise
 * @param conversationId the customer's thread, or null when messaging was having
 *                 a moment at assignment — the client draws no button rather
 *                 than one that cannot work
 */
record CourierJobDto(UUID id, String status, String merchantName,
                     Double merchantLatitude, Double merchantLongitude,
                     String addressLabel, String addressLine, String addressNote,
                     Double addressLatitude, Double addressLongitude,
                     /* Who is at the door, when the person paying is not
                      * (Phase 4 M6). Blank otherwise. The name and nothing
                      * else — the recipient's phone number is on the order and
                      * never leaves it, because a courier needs to know who to
                      * hand a bag to, not how to reach a stranger later. */
                     String recipientName,
                     int itemCount, String note, String handoffMode,
                     long payMinor, String currency, UUID conversationId,
                     /* One per merchant since Phase 4 M3, in collection order.
                      * The single merchantName/lat/lng above stay populated
                      * with the next uncollected stop, so an older client's
                      * one-restaurant screen always points at the right
                      * counter. */
                     List<CourierStopDto> stops,
                     OffsetDateTime readyAt, OffsetDateTime pickedUpAt,
                     OffsetDateTime statusChangedAt) {
}

/**
 * One counter on the courier's route. {@code collected} flips when the code
 * typed at that counter matched — the code itself is on the kitchen's screen
 * and never here, which is the whole point of there being one per kitchen.
 */
record CourierStopDto(UUID subOrderId, String merchantName,
                      Double latitude, Double longitude, int itemCount,
                      boolean collected, OffsetDateTime readyAt) {
}

/** Wrapper so "not carrying anything" is a 200 with {@code job: null}. */
record CourierJobResponse(CourierJobDto job) {
}

/**
 * The answer to a handoff attempt — and it is an <b>answer</b>, which is why
 * both verbs return it with a 200 whether or not the code was right.
 *
 * <p>A courier at a door who typed a 7 for a 1 has not made a bad request, and
 * dressing that up as a 4xx would put an error banner in front of somebody
 * holding a bag of food. The client shows {@code message} in place and leaves
 * what they typed alone. Written for a person standing outside, so it never
 * says how wrong the code was: "one digit off" is a hint, and a hint is a
 * shorter guess list.
 *
 * @param attemptsLeft how many wrong PINs remain before the photo fallback
 *                     opens, or <b>-1</b> where attempts are not counted at all
 *                     — which is what the pickup endpoint always returns
 * @param supportUnlocked the fallback is open: this delivery may now be completed
 *                     with a photo instead of a PIN
 * @param job          the courier's job as it now stands, present on a refusal
 *                     too. A wrong code should not blank the screen that is
 *                     telling them where they are
 */
record HandoffResultDto(boolean accepted, String message, int attemptsLeft,
                        boolean supportUnlocked, CourierJobDto job) {
}

/** The pickup code, as typed. Optional, because "I typed nothing" is one of the
 *  outcomes this endpoint has an answer for rather than a validation failure. */
record PickupHandoffRequest(@Size(max = 16) String pickupCode) {
}

/** The delivery PIN, as typed. Absent for a photo or contactless handoff. */
record DeliveryHandoffRequest(@Size(max = 16) String pin) {
}

/**
 * A presigned PUT for the drop-off photo. Shaped like the partner document
 * upload because it is the same mechanism — {@code MediaDocumentApi}'s private
 * prefix, no public URL, a short expiry.
 *
 * <p>The difference is that nothing is sent back: the server has already stamped
 * the key it minted onto the order, so there is no "attach" call and no request
 * anywhere that accepts a client-supplied key. {@code objectKey} is returned for
 * the client's own logging and is not a credential — it grants nothing without a
 * signature.
 */
record ProofUploadDto(String uploadUrl, String objectKey, String contentType,
                      long expiresSeconds) {
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
                /* Echoed back (Phase 4 M4), so a client can tell that the
                 * server agreed to price a collection rather than assuming it:
                 * a build talking to a backend that predates this field would
                 * otherwise draw a pickup checkout over a quote with a delivery
                 * fee in it. */
                String fulfilmentKind,
                /* The per-merchant breakdown (Phase 4 M3), so a checkout sheet
                 * can group by kitchen. Sums to the flat fields above. */
                List<MerchantQuoteDto> merchants,
                /* The window a scheduled order may land in (Phase 4 M5), for
                 * this exact basket. The earliest is not a constant — it is
                 * the slowest kitchen in the cart plus the window they get to
                 * answer in, floored by config — so the server computes it
                 * here rather than leaving a picker to guess and be refused
                 * afterwards. */
                OffsetDateTime earliestScheduleAt, OffsetDateTime latestScheduleAt,
                long walletAvailableMinor, boolean walletCovers, long shortfallMinor) {
}

/** One merchant's slice of a quote. */
record MerchantQuoteDto(UUID merchantId, String name, int subtotalCents,
                        int deliveryFeeCents, int discountCents,
                        String promotionCode, String promotionLabel) {
}

/**
 * One merchant's basket inside a multi-merchant checkout (Phase 4 M3). The
 * promotion code is per basket because a promotion is one merchant's own
 * campaign; the top-level code on the request is tried against every basket
 * instead, for the client with one code field.
 */
record BasketRequest(@NotNull UUID merchantId,
                     @NotEmpty @Size(max = 40) List<@Valid OrderLineRequest> lines,
                     @Size(max = 32) String promotionCode) {
}

/** Either the legacy single-merchant fields or {@code baskets} — one of the
 *  two is required, checked in the service where the message can say so. */
record QuoteRequest(UUID merchantId,
                    @Size(max = 40) List<@Valid OrderLineRequest> lines,
                    @Size(max = 10) List<@Valid BasketRequest> baskets,
                    @Size(max = 32) String promotionCode,
                    @Min(0) @Max(100_000) int tipCents,
                    /* DELIVERY | PICKUP, optional (Phase 4 M4). Null, blank or
                     * unrecognised is DELIVERY — the kind that works
                     * everywhere. */
                    @Size(max = 16) String fulfilmentKind) {
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

/**
 * Wrapper so "no order in flight" is a 200 with {@code order: null}, not a 404.
 *
 * <p>Two lists since Phase 4 M5, and both are additive — {@code order} keeps
 * carrying the one a client draws its tracking card from, which in the
 * overwhelmingly common case is the only live order there is.
 *
 * @param orders every order actually being fulfilled, soonest first. More than
 *               one is possible now: a scheduled order promotes on its own
 *               clock and can land while another is in flight, and holding
 *               somebody's dinner back over a rule about screens would be the
 *               worse answer
 * @param scheduled orders no kitchen has been told about yet — upcoming, still
 *               free to change or cancel, and deliberately <em>not</em> in
 *               {@code orders}: an order three days away is not in flight, and
 *               a countdown for one is arithmetic rather than information
 */
record ActiveOrderResponse(OrderDto order, List<OrderDto> orders, List<OrderDto> scheduled) {
}

// MARK: Disputes (Phase 4 M6, SPECS §5)

/**
 * A reported problem, as the customer who reported it sees it.
 *
 * <p>Carries no photo URLs and no payer: the pictures are theirs and they know
 * what they sent, and which of three parties funded a refund is an operator's
 * business rather than an invitation to argue with a restaurant about it.
 */
record DisputeDto(UUID id, UUID subOrderId, String reason, String note, String state,
                  int claimedCents, int refundCents, String resolutionNote,
                  int photoCount, List<DisputedItemDto> items,
                  OffsetDateTime createdAt, OffsetDateTime resolvedAt) {
}

record DisputedItemDto(UUID menuItemId, String name, int unitPriceCents, int qty) {
}

/**
 * The same dispute on the operator's screen, with the thing they cannot
 * otherwise know: what each of the three parties was actually paid for this
 * order, and what has already been refunded on it.
 *
 * <p>That is the whole point of this DTO. Deciding a refund means knowing
 * whether the restaurant can even afford it, and an operator doing that
 * arithmetic off a receipt in another tab is an operator who will eventually get
 * it wrong in somebody's favour.
 */
record AdminDisputeDto(DisputeDto dispute, UUID orderId, UUID userId, String merchantName,
                       int orderTotalCents, String currency, String fulfilmentKind,
                       String suggestedPayer,
                       long merchantReceivedMinor, long courierReceivedMinor,
                       long platformReceivedMinor, int alreadyRefundedCents,
                       List<String> photoUrls, String proofPhotoUrl,
                       String resolvedBy, OffsetDateTime deliveredAt) {
}

/** What went wrong. {@code items} is ids and quantities only — never amounts,
 *  the same rule checkout follows, because a claim the client priced is a claim
 *  the client can inflate. */
record FileDisputeRequest(UUID subOrderId,
                          @NotBlank @Size(max = 32) String reason,
                          @Size(max = 600) String note,
                          @Size(max = 40) List<@Valid DisputedItemRequest> items) {
}

record DisputedItemRequest(@NotNull UUID menuItemId, @Min(1) @Max(50) int qty) {
}

/** An operator's decision. {@code payer} is required on a refund and is the
 *  decision itself — the reason only ever suggests one. */
record ResolveDisputeRequest(@Min(0) @Max(10_000_000) int refundCents,
                             @Size(max = 16) String payer,
                             @Size(max = 600) String note) {
}

record OrderLineRequest(@NotNull UUID menuItemId, @Min(1) @Max(50) int qty) {
}

/** {@code addressId} is a saved address of the caller's; the older
 *  {@code addressLabel} free-text form is still accepted so a client that
 *  predates saved addresses keeps working. One of the two is required — and so
 *  is one of {@code merchantId + lines} (the pre-M3 single-merchant shape) or
 *  {@code baskets}, checked in the service where the message can say so. */
record PlaceOrderRequest(UUID merchantId,
                         @Size(max = 40) List<@Valid OrderLineRequest> lines,
                         @Size(max = 10) List<@Valid BasketRequest> baskets,
                         UUID addressId,
                         @Size(max = 120) String addressLabel,
                         @Size(max = 280) String note,
                         /* A code, never an amount: what a discount is worth is
                          * read server-side from the promotion it names. */
                         @Size(max = 32) String promotionCode,
                         @Min(0) @Max(100_000) int tipCents,
                         /* PIN | PHOTO | CONFIRM, optional. Null, blank or a
                          * word this build has never heard of all mean the
                          * configured default — a checkout must not fail on a
                          * word, and it can be changed later anyway. */
                         @Size(max = 16) String handoffMode,
                         /* DELIVERY | PICKUP, optional (Phase 4 M4). Unlike the
                          * handoff mode this one is *not* changeable later: it
                          * is what the order was priced for. Unrecognised means
                          * DELIVERY, and a PICKUP at a restaurant that does not
                          * offer collection is refused out loud — that is a
                          * refusal somebody can act on, unlike being silently
                          * given the other kind. */
                         @Size(max = 16) String fulfilmentKind,
                         /* Ordering for somebody else (Phase 4 M6). A name is
                          * what makes it one — the phone is optional and is
                          * never disclosed to the courier, existing so that a
                          * recipient with no account has somewhere to be
                          * reached from later. Both ignored on a collection. */
                         @Size(max = 80) String recipientName,
                         @Size(max = 32) String recipientPhone,
                         /* When the customer wants it (Phase 4 M5), or null
                          * for "now" — which is what every client that
                          * predates this field sends, and what the great
                          * majority of orders are. Refused rather than
                          * rounded when it is too soon or too far out, with
                          * the message naming the earliest time that would
                          * have worked: silently moving somebody's dinner is
                          * worse than telling them it cannot be then. */
                         OffsetDateTime scheduledFor) {
}

record RateOrderRequest(@Min(1) @Max(5) int rating) {
}

/**
 * A public link to follow a delivery (Phase 4 M6).
 *
 * @param message wording the app can hand straight to the share sheet, so the
 *                sentence somebody sends is written here rather than in three
 *                clients that will each phrase it differently
 */
record ShareOrderDto(String url, OffsetDateTime expiresAt, int viewCount, String message) {
}
