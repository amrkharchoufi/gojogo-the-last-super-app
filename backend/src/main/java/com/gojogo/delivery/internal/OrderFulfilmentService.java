package com.gojogo.delivery.internal;

import com.gojogo.delivery.OrderStatusChanged;
import com.gojogo.dispatch.Assignment;
import com.gojogo.dispatch.DispatchApi;
import com.gojogo.dispatch.DispatchRequest;
import com.gojogo.dispatch.JobKind;
import com.gojogo.dispatch.WorkerKind;
import com.gojogo.media.MediaDocumentApi;
import com.gojogo.messaging.ConversationContext;
import com.gojogo.messaging.MessagingApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Everything that happens to an order after it is placed, now that real people
 * do it.
 *
 * <p>Until Phase 4 M1 this file did not exist, because none of it was anybody's
 * decision: {@code OrderFulfilmentJob} read a clock and walked every order to
 * wherever a timeline said it should be, inventing a kitchen that always took
 * twenty seconds and a courier from a roster of four names. The state machine,
 * the events and the API were real; the actors were not. This is the swap 2b M4
 * was designed for, and what it means concretely is that <b>every transition
 * below is now caused by somebody</b> — a restaurant accepting, a courier
 * accepting, a courier picking food up, a courier handing it over.
 *
 * <p>Kept out of {@link DeliveryService}, which is the customer's side of the
 * same schema, for the reason {@link MerchantManagementService} is: that class
 * already owns the catalog, addresses, quoting and placement, and the file this
 * one replaced was separate too.
 *
 * <p><b>The one mechanism worth understanding is the courier trigger.</b> A
 * courier is not looked for when the order is placed — they would arrive to a
 * cold counter and wait unpaid for twenty minutes — and not when the food is
 * ready either, because then the food waits instead. The search starts at
 * {@code readyAt − pickupLead}, and that is not a new mechanism: it is
 * {@link DispatchRequest#startAfter}, which dispatch has carried since M1
 * precisely for this and which no caller had ever used. A job whose first wave
 * is in the future is all "approaching readiness" (SPECS §3) ever was.
 *
 * <p><b>Phase 4 M2 makes the two courier taps evidence rather than assertions.</b>
 * M1's "I have the food" and "I handed it over" moved an order and then moved
 * money on nothing but somebody's word. Now a pickup is backed by a code only
 * the counter can show and a handoff by a PIN only the customer knows, a photo
 * of the doorstep, or an explicit choice to need neither. Nothing about the
 * state machine changed to accommodate any of it — a failed handoff leaves the
 * order in {@code DELIVERING}, because that is exactly what it is: the courier
 * still has the food.
 */
@Service
class OrderFulfilmentService {

    private static final Logger log = LoggerFactory.getLogger(OrderFulfilmentService.class);

    /** What a restaurant is looking at: everything not finished. */
    private static final Set<OrderStatus> LIVE = EnumSet.of(OrderStatus.CONFIRMED,
        OrderStatus.PREPARING, OrderStatus.COURIER_TO_RESTAURANT, OrderStatus.DELIVERING);

    private static final Set<OrderStatus> TERMINAL =
        EnumSet.of(OrderStatus.DELIVERED, OrderStatus.CANCELLED);

    /** A courier's job is theirs from the moment they take it until they hand it
     *  over — two of the six statuses, and never more than one order. */
    private static final Set<OrderStatus> COURIER_LIVE =
        EnumSet.of(OrderStatus.COURIER_TO_RESTAURANT, OrderStatus.DELIVERING);

    /** Drop-off photos live under media's private prefix, in their own folder —
     *  the point of the {@code folder} argument is that private objects stay
     *  separable by purpose, and a doorstep is not a driving licence. */
    private static final String PROOF_FOLDER = "delivery-proof";
    private static final String PROOF_CONTENT_TYPE = "image/jpeg";

    private final OrderRepository orders;
    private final MerchantRepository merchants;
    private final OrderPayments payments;
    private final DeliveryPolicy policy;
    private final DispatchApi dispatch;
    private final ProfileApi profiles;
    private final MessagingApi messaging;
    private final MediaDocumentApi privateMedia;
    private final ApplicationEventPublisher events;

    OrderFulfilmentService(OrderRepository orders, MerchantRepository merchants,
                           OrderPayments payments, DeliveryPolicy policy,
                           DispatchApi dispatch, ProfileApi profiles,
                           MessagingApi messaging, MediaDocumentApi privateMedia,
                           ApplicationEventPublisher events) {
        this.orders = orders;
        this.merchants = merchants;
        this.payments = payments;
        this.policy = policy;
        this.dispatch = dispatch;
        this.profiles = profiles;
        this.messaging = messaging;
        this.privateMedia = privateMedia;
        this.events = events;
    }

    // MARK: The restaurant's side

    /** The live queue, oldest first — a kitchen works in the order things arrived. */
    @Transactional(readOnly = true)
    List<MerchantOrderDto> queue(UUID ownerId) {
        Merchant merchant = requireMine(ownerId);
        return orders.findByMerchantIdAndStatusInOrderByPlacedAtAsc(merchant.getId(), LIVE)
            .stream().map(this::toMerchantOrderDto).toList();
    }

    @Transactional(readOnly = true)
    List<MerchantOrderDto> recent(UUID ownerId, int limit) {
        Merchant merchant = requireMine(ownerId);
        return orders.findByMerchantIdAndStatusInOrderByStatusChangedAtDesc(
                merchant.getId(), TERMINAL, PageRequest.of(0, Math.clamp(limit, 1, 50)))
            .stream().map(this::toMerchantOrderDto).toList();
    }

    /**
     * The restaurant takes the order and says how long it needs.
     *
     * <p>The prep estimate is the load-bearing part, and it is why this is not a
     * bare "accept" button: it is the only thing in the system that knows when
     * the food will be ready, and everything downstream — when a courier is
     * looked for, what the customer's countdown says, when the courier should
     * arrive — is derived from it. A missing or absurd number falls back to the
     * configured default rather than failing: an accept that can be rejected by
     * validation is an accept somebody in a kitchen does not make.
     *
     * <p><b>Both handoff codes are minted here</b>, and this is the moment for
     * two reasons. It is the first point at which there is a bag to hand over —
     * a code on an order the restaurant may still refuse is a code for a
     * delivery that never happens. And it is early enough that no screen ever
     * has to render a null: by the time a courier is even looked for, the
     * kitchen has a code to read out and the customer has a PIN to give.
     */
    @Transactional
    MerchantOrderDto accept(UUID ownerId, UUID orderId, Integer requestedPrepMinutes) {
        Merchant merchant = requireMine(ownerId);
        CustomerOrder order = requireForMerchant(merchant, orderId);
        if (order.getStatus() != OrderStatus.CONFIRMED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                order.getStatus() == OrderStatus.CANCELLED
                    ? "That order was cancelled"
                    : "You've already accepted that order");
        }
        int prep = requestedPrepMinutes == null || requestedPrepMinutes <= 0
            ? policy.defaultPrepMinutes()
            : Math.min(requestedPrepMinutes, policy.maxPrepMinutes());

        OffsetDateTime now = OffsetDateTime.now();
        order.accepted(now, prep, now.plusMinutes(prep + policy.dropoffMinutes()));
        int digits = policy.handoffCodeLength();
        order.mintHandoffCodes(HandoffCodes.numeric(digits), HandoffCodes.numeric(digits));
        order.moveTo(OrderStatus.PREPARING, now);
        // Flushed before dispatch is asked, so an order that fails to save never
        // puts a job in front of a courier.
        orders.flush();
        findCourierFor(order, merchant);
        publish(order, merchant.getName());
        return toMerchantOrderDto(order);
    }

    /**
     * The restaurant says no. Only before they have accepted — once a kitchen
     * has started, "reject" is a cancellation with food already made, which is a
     * dispute (SPECS §5) rather than a button.
     */
    @Transactional
    MerchantOrderDto reject(UUID ownerId, UUID orderId, String reason) {
        Merchant merchant = requireMine(ownerId);
        CustomerOrder order = requireForMerchant(merchant, orderId);
        if (order.getStatus() != OrderStatus.CONFIRMED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Too late to turn that one down");
        }
        cancel(order, merchant.getName(), reason == null || reason.isBlank()
            ? "The restaurant couldn't take this order" : reason.trim());
        return toMerchantOrderDto(order);
    }

    /**
     * The food is ready — sooner or later than the kitchen guessed.
     *
     * <p>Worth having even though the courier has usually been found by now:
     * {@code readyAt} is what the pickup time on their screen is drawn from, and
     * a courier told the wrong one either waits at a counter or arrives to food
     * that has been sitting. It does not change the order's status, because
     * "cooked" is not a stage of an order the customer can act on — their food
     * is still coming, and the screen still says so.
     */
    @Transactional
    MerchantOrderDto markReady(UUID ownerId, UUID orderId) {
        Merchant merchant = requireMine(ownerId);
        CustomerOrder order = requireForMerchant(merchant, orderId);
        if (order.getStatus() != OrderStatus.PREPARING
            && order.getStatus() != OrderStatus.COURIER_TO_RESTAURANT) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That order isn't being prepared");
        }
        OffsetDateTime now = OffsetDateTime.now();
        order.readyNow(now, now.plusMinutes(policy.dropoffMinutes()));
        return toMerchantOrderDto(order);
    }

    // MARK: Asking dispatch

    /**
     * Opens the courier search, timed to the kitchen.
     *
     * <p>Never throws into the accept that called it. A restaurant's accept is
     * not the right transaction to fail because dispatch had a bad moment — the
     * order is accepted, the kitchen is cooking, and an order with no search
     * running is visibly stuck rather than silently wrong: it stays
     * {@code SEARCHING = NONE} and reads as a failed search to everybody looking
     * at it.
     */
    private void findCourierFor(CustomerOrder order, Merchant merchant) {
        try {
            dispatch.request(new DispatchRequest(JobKind.DELIVERY, order.getId(),
                WorkerKind.COURIER, policy.courierCategories(), order.getUserId(),
                merchant.getLatitude(), merchant.getLongitude(), merchant.getName(),
                order.getAddressLatitude(), order.getAddressLongitude(),
                order.getAddressLabel(), order.getNote(),
                order.getReadyAt().minusSeconds(policy.pickupLeadSeconds())));
            order.searchingForCourier();
        } catch (RuntimeException dispatchIsHavingAMoment) {
            log.error("Could not open a courier search for order {}: {}",
                order.getId(), dispatchIsHavingAMoment.toString());
            order.noCourierFound();
        }
    }

    /**
     * A courier took it.
     *
     * <p><b>{@code REQUIRES_NEW}, and it is load-bearing.</b> This runs from an
     * {@code AFTER_COMMIT} listener, where the resources of the transaction that
     * just committed are still bound to the thread — so plain {@code REQUIRED}
     * joins a transaction that is already finished and the first flush throws
     * "no transaction is in progress". That exact defect shipped in Phase 3 M3
     * and was live for a day (PROGRESS, 2026-08-01): dispatch had assigned the
     * job, so the worker was marked busy for a ride that never confirmed. Same
     * shape here, same fix, written this way from the start.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void courierAssigned(UUID orderId, Assignment assignment) {
        CustomerOrder order = orders.findById(orderId).orElse(null);
        if (order == null) return;
        if (order.getStatus().isTerminal()) {
            // Cancelled between the accept and the assignment. Hand the courier
            // straight back rather than leaving them busy for an order nobody
            // is waiting on.
            dispatch.cancel(JobKind.DELIVERY, orderId, false);
            return;
        }
        if (order.getStatus() != OrderStatus.PREPARING) {
            // Already assigned, or further along. A redelivered event must not
            // stand the courier down from a delivery they are in the middle of,
            // which is what treating "not PREPARING" as "cancelled" would do.
            return;
        }
        String name = profiles.findById(assignment.userId())
            .map(OrderFulfilmentService::displayName)
            .orElse("Your courier");
        order.assignCourier(assignment.workerId(), assignment.userId(), name,
            vehicleLabel(assignment), BigDecimal.valueOf(assignment.rating()),
            assignment.completedCount());
        order.moveTo(OrderStatus.COURIER_TO_RESTAURANT, OffsetDateTime.now());
        Merchant merchant = merchants.findById(order.getMerchantId()).orElse(null);
        openConversation(order, merchant);
        publish(order, merchant == null ? "Restaurant" : merchant.getName());
    }

    /**
     * Puts the customer and the courier in a thread, with a card back to the
     * order.
     *
     * <p>This is the <b>third</b> consumer of the {@link ConversationContext}
     * seam 2b M3 built — a listing, then a ride, now an order — and the third
     * one cost the messaging module nothing: it still stores the card and echoes
     * it without knowing what any of the three are. That is the entire argument
     * for a generic reference rather than a {@code listingId} column, made for
     * the second time.
     *
     * <p>Failures are logged and swallowed, copying {@code RideService} exactly
     * and for the same reason: a chat that did not open is an inconvenience, and
     * rolling back a courier's assignment over one would leave a person on a
     * bike outside a restaurant that is no longer expecting them. The column
     * stays null and the client simply draws no message button.
     */
    private void openConversation(CustomerOrder order, Merchant merchant) {
        if (order.getCourierUserId() == null) return;
        try {
            int items = order.getLines().stream().mapToInt(OrderLine::getQty).sum();
            UUID conversation = messaging.openDirectConversation(
                order.getUserId(), order.getCourierUserId(),
                new ConversationContext("order", order.getId().toString(),
                    merchant == null ? "Your order" : merchant.getName(),
                    items == 1 ? "1 item on the way" : items + " items on the way",
                    merchant == null ? null : merchant.getImageUrl()));
            order.attachConversation(conversation);
        } catch (RuntimeException messagingIsHavingAMoment) {
            log.warn("Couldn't open the chat for order {}: {}",
                order.getId(), messagingIsHavingAMoment.toString());
        }
    }

    /**
     * Nobody took it, and there is no second search.
     *
     * <p>Dispatch's job row is unique on (kind, ref) by design, so re-asking for
     * the same order would need a platform verb to re-open a closed job — and
     * asking a second time is the same question to the same empty city: every
     * ring within range has already been searched for the whole request window.
     * So the order is flagged rather than retried, and deliberately <em>not</em>
     * cancelled: the food may already be cooked, and throwing away a made dinner
     * is a decision for the people involved rather than for a sweep. Both sides
     * see it, and the customer can still cancel for a full release.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void courierSearchFailed(UUID orderId) {
        CustomerOrder order = orders.findById(orderId).orElse(null);
        if (order == null || order.getStatus() != OrderStatus.PREPARING) return;
        order.noCourierFound();
        log.warn("No courier accepted order {} — it is flagged for the customer and "
            + "the restaurant", orderId);
    }

    // MARK: The courier's side

    /** The one order this courier is carrying, plus what they have earned. */
    @Transactional(readOnly = true)
    CourierJobResponse job(UUID courierUserId) {
        CustomerOrder order = orders
            .findFirstByCourierUserIdAndStatusInOrderByStatusChangedAtDesc(
                courierUserId, COURIER_LIVE)
            .orElse(null);
        return new CourierJobResponse(order == null ? null : toCourierJobDto(order));
    }

    @Transactional(readOnly = true)
    List<CourierJobDto> deliveries(UUID courierUserId, int limit) {
        List<CustomerOrder> page = orders.findByCourierUserIdAndStatusOrderByStatusChangedAtDesc(
            courierUserId, OrderStatus.DELIVERED, PageRequest.of(0, Math.clamp(limit, 1, 50)));
        // One query for the restaurants rather than one per row — the same thing
        // the customer's own history does, and the difference between 1 query
        // and 50 for a screen somebody scrolls.
        Map<UUID, Merchant> byId = merchants
            .findAllById(page.stream().map(CustomerOrder::getMerchantId).collect(Collectors.toSet()))
            .stream().collect(Collectors.toMap(Merchant::getId, Function.identity()));
        return page.stream().map(o -> toCourierJobDto(o, byId.get(o.getMerchantId()))).toList();
    }

    /**
     * They have the food, and they can prove they were standing at the counter.
     *
     * <p>The proof is a code <b>the merchant's screen shows and the courier
     * types</b>, which is the reverse of SPECS §5 and deliberate. The spec has
     * the courier show a code and the merchant confirm it; the party who must
     * act should be the party with the incentive. A merchant who forgets to tap
     * leaves a courier holding food they cannot mark collected and cannot be
     * paid for, whereas a courier is motivated to finish the step and can only
     * learn the code by standing at that counter — which is the fact the code
     * exists to prove.
     *
     * <p><b>A wrong code here is never counted and never locks anybody out</b>,
     * and the asymmetry with the delivery PIN is the point. At the door, the
     * risk is a courier marking an undelivered order delivered, so the attempts
     * are counted. At the counter, the merchant is standing right there: the
     * code is a check rather than a gate, and a courier who fails it three times
     * with the food in front of them must not be locked out of a delivery
     * everybody in the room can see is theirs. {@code attemptsLeft} is
     * {@code -1} on this endpoint to say "not counted" rather than "none left".
     *
     * <p>From here the order can no longer be cancelled — the rule that predates
     * real couriers, now with a real event behind it.
     */
    @Transactional
    HandoffResultDto pickedUp(UUID courierUserId, UUID orderId, String typedCode) {
        CustomerOrder order = requireForCourier(courierUserId, orderId);
        if (order.getStatus() != OrderStatus.COURIER_TO_RESTAURANT) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                order.getStatus() == OrderStatus.DELIVERING
                    ? "You've already picked that up"
                    : "That order isn't waiting for you any more");
        }
        // A blank code on the row is an order accepted before V38. It is not a
        // locked door: there is no code for anybody in that restaurant to read
        // out, so there is nothing to check and the collect works as it did in
        // M1. A migration must not lock a courier out of food they are holding.
        if (!order.getPickupCode().isBlank()) {
            String typed = HandoffCodes.digitsOf(typedCode);
            if (typed.isEmpty()) {
                return refused(order, "Ask the restaurant for the pickup code", -1, false);
            }
            if (!typed.equals(order.getPickupCode())) {
                // Never says how wrong. "One digit off" is a hint, and a hint
                // is a shorter guess list.
                return refused(order, "That code doesn't match — check the screen at the counter",
                    -1, false);
            }
        }
        OffsetDateTime now = OffsetDateTime.now();
        order.pickedUp(now);
        order.moveTo(OrderStatus.DELIVERING, now);
        publish(order, merchantName(order.getMerchantId()));
        return new HandoffResultDto(true, "Collected", -1, false, toCourierJobDto(order));
    }

    /**
     * Handed over. The one transition that moves money: the hold placed at
     * checkout is split between the merchant, the platform and — since Phase 4
     * M1 — the courier who actually carried it. Which is exactly why this is the
     * handoff that is verified and counted: everything upstream can be redone,
     * and this one pays somebody.
     *
     * <p>Three ways to satisfy it, chosen by the customer and readable off the
     * order:
     *
     * <ul>
     *   <li><b>CONFIRM</b>, and any order whose PIN is blank because it predates
     *       V38 — a tap, exactly as M1 did it.</li>
     *   <li><b>PIN</b> — the six digits the customer has on their screen. A
     *       mismatch is a 200 with {@code accepted=false}: a courier who typed a
     *       7 for a 1 has not made a bad request, and an error banner is the
     *       wrong thing to put in front of somebody holding a bag of food.</li>
     *   <li><b>PHOTO</b> — no PIN, but the drop-off must actually have been
     *       photographed. "Requires a photo" means the key is on the row, which
     *       only the presign endpoint can put there.</li>
     * </ul>
     *
     * <p><b>The fallback, and it is a deliberate hole.</b> Once the wrong-PIN
     * attempts reach the configured maximum, a PIN order may be completed by the
     * photo path instead. That can be abused — fail three times on purpose and
     * photograph a doorstep — and the alternative is worse: a courier stranded
     * in the street with food nobody will accept, because the customer is asleep,
     * has the wrong screen open, or gave the phone to a child. The mitigations
     * are that the abuse is recorded on the row rather than inferred later
     * ({@code handoff_attempts} is never reset), the photo is evidence in a
     * dispute, and the customer is shown both the count and the picture. A
     * mechanism whose failure mode is "the delivery does not happen" is not a
     * safety mechanism.
     *
     * <p>Dispatch is told inside the same transaction, which is what frees the
     * courier for the next offer. A rating is deliberately <em>not</em> passed:
     * the customer's order rating is about the food as much as the trip, and a
     * two star for a cold burger must not land on the record of the person who
     * cycled it across town.
     */
    @Transactional
    HandoffResultDto delivered(UUID courierUserId, UUID orderId, String typedPin) {
        CustomerOrder order = requireForCourier(courierUserId, orderId);
        if (order.getStatus() != OrderStatus.DELIVERING) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                order.getStatus() == OrderStatus.DELIVERED
                    ? "You've already delivered that one"
                    : "Pick the order up first");
        }
        int max = policy.handoffMaxAttempts();
        boolean unlocked = order.getHandoffAttempts() >= max;
        String pin = HandoffCodes.digitsOf(typedPin);

        // The photo path: taken when the customer asked for it, and when a PIN
        // order has burned through its attempts and the courier is not offering
        // a PIN. A correct PIN still works after lockout — the fallback adds a
        // way through, it does not close the front door.
        boolean byPhoto = order.getHandoffMode() == HandoffMode.PHOTO
            || (unlocked && pin.isEmpty());
        if (byPhoto) {
            if (order.getProofPhotoKey() == null) {
                return refused(order, "Take a photo of the drop-off first",
                    attemptsLeft(order, max), unlocked);
            }
        } else if (order.getHandoffMode() == HandoffMode.PIN
            && !order.getDeliveryPin().isBlank()) {
            if (!pin.equals(order.getDeliveryPin())) {
                // An empty submission counts too, and that is deliberate rather
                // than an oversight: a courier at a door nobody is answering has
                // no PIN to type, and if "no PIN" cost nothing they could never
                // reach the fallback that exists for exactly their situation.
                // Three taps is the honest way out of a silent doorstep.
                order.handoffRefused();
                boolean nowUnlocked = order.getHandoffAttempts() >= max;
                String message;
                if (nowUnlocked) {
                    message = "That's not the PIN. You can take a photo of the drop-off instead.";
                } else if (pin.isEmpty()) {
                    message = "Ask them for the PIN on their order screen";
                } else {
                    message = "That's not the PIN — check it with them and try again";
                }
                return refused(order, message, attemptsLeft(order, max), nowUnlocked);
            }
        }

        String merchantName = merchantName(order.getMerchantId());
        order.moveTo(OrderStatus.DELIVERED, OffsetDateTime.now());
        payments.settle(order, merchantName);
        dispatch.complete(JobKind.DELIVERY, order.getId(), null);
        publish(order, merchantName);
        return new HandoffResultDto(true, "Delivered", attemptsLeft(order, max),
            unlocked, toCourierJobDto(order));
    }

    /**
     * A presigned PUT for the drop-off photo, with the key it minted already
     * stamped on the order.
     *
     * <p><b>No endpoint anywhere accepts a client-supplied key.</b> The partner
     * document flow presigns and then takes the key back on an attach, which
     * needs a prefix check to stop somebody attaching any object in the bucket;
     * here there is nothing to check, because the server never asks. That is
     * only possible because the two calls are one transaction and the key has
     * exactly one owner — this order.
     *
     * <p>Replacing an earlier key deletes the object behind it. Nothing sweeps
     * the private prefix (the cleanup job only knows about public media), so a
     * courier retaking a photo would otherwise leave a picture of a stranger's
     * front door in the bucket forever.
     */
    @Transactional
    ProofUploadDto proofPhotoUpload(UUID courierUserId, UUID orderId) {
        CustomerOrder order = requireForCourier(courierUserId, orderId);
        if (order.getStatus() != OrderStatus.DELIVERING) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                order.getStatus() == OrderStatus.DELIVERED
                    ? "You've already delivered that one"
                    : "Pick the order up first");
        }
        // The server picks the format rather than the client. A proof photo is
        // not a document somebody chooses the type of, every phone can produce
        // a JPEG, and one content type means the presigned PUT and the header
        // the client sends cannot disagree — which is the failure that looks
        // like a broken upload and is actually a mismatched signature.
        MediaDocumentApi.DocumentUpload upload =
            privateMedia.presignDocumentUpload(courierUserId, PROOF_FOLDER, PROOF_CONTENT_TYPE);
        String previous = order.getProofPhotoKey();
        order.proofPhotographedAt(upload.objectKey());
        if (previous != null && !previous.equals(upload.objectKey())) {
            privateMedia.deleteDocument(previous);
        }
        return new ProofUploadDto(upload.uploadUrl(), upload.objectKey(),
            upload.contentType(), upload.expiresSeconds());
    }

    /**
     * How many wrong PINs are left before the fallback opens.
     *
     * <p>Only a real budget where wrong PINs are counted at all — a contactless
     * or plain-confirm order gets {@code -1} ("not counted"), because a number
     * there would read as one and the client would draw a countdown for
     * something nobody can spend. Never negative either: a courier who has
     * somehow failed five times against a maximum of three is told "0", not
     * "-2".
     */
    private static int attemptsLeft(CustomerOrder order, int max) {
        if (order.getHandoffMode() != HandoffMode.PIN) return -1;
        return Math.max(0, max - order.getHandoffAttempts());
    }

    /** A refusal carries the job back with it — a wrong code must not blank the
     *  screen that is telling the courier where they are. */
    private HandoffResultDto refused(CustomerOrder order, String message,
                                     int attemptsLeft, boolean supportUnlocked) {
        return new HandoffResultDto(false, message, attemptsLeft, supportUnlocked,
            toCourierJobDto(order));
    }

    // MARK: Timeouts (called by OrderTimeoutJob)

    /**
     * Orders nobody in a kitchen ever answered.
     *
     * <p>The simulation had no way to fail, so it needed no sweep; a real
     * restaurant can simply not look at their tablet, and an order left in
     * CONFIRMED holds a customer's money in escrow and their one live-order slot
     * with it, forever. The same query catches the rows stranded by this
     * milestone's own deploy — an order in flight when the fulfilment job was
     * deleted also has no {@code acceptedAt}, which is exactly what "nobody ever
     * accepted this" looks like.
     */
    @Transactional(readOnly = true)
    List<UUID> unansweredOrderIds(int limit) {
        OffsetDateTime cutoff = OffsetDateTime.now().minusMinutes(policy.acceptTimeoutMinutes());
        return orders.findByStatusNotInAndAcceptedAtIsNullAndPlacedAtBeforeOrderByPlacedAtAsc(
                TERMINAL, cutoff, PageRequest.of(0, limit))
            .stream().map(CustomerOrder::getId).toList();
    }

    @Transactional
    void timeOut(UUID orderId) {
        CustomerOrder order = orders.findById(orderId).orElse(null);
        if (order == null || order.getStatus().isTerminal() || order.getAcceptedAt() != null) {
            return;
        }
        cancel(order, merchantName(order.getMerchantId()),
            "The restaurant didn't answer in time — you haven't been charged");
    }

    // MARK: Shared

    /**
     * Ends an order and gives the money back. Dispatch is told whatever stage it
     * had reached, and told nothing at all if it never heard of this order —
     * {@code cancel} is safe for a job that was never requested, which is what
     * lets this one method serve a rejection, a timeout and a customer changing
     * their mind.
     */
    void cancel(CustomerOrder order, String merchantName, String reason) {
        order.moveTo(OrderStatus.CANCELLED, OffsetDateTime.now());
        order.cancelledBecause(reason);
        // Never the courier's fault: they are being stood down, not walking away.
        dispatch.cancel(JobKind.DELIVERY, order.getId(), false);
        payments.release(order);
        publish(order, merchantName);
    }

    private void publish(CustomerOrder order, String merchantName) {
        events.publishEvent(new OrderStatusChanged(order.getId(), order.getUserId(),
            merchantName, order.getStatus().name(), Eta.minutesLeft(order)));
    }

    private Merchant requireMine(UUID ownerId) {
        return merchants.findFirstByOwnerId(ownerId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "You don't manage a restaurant"));
    }

    /** 404 rather than 403 for another restaurant's order — the same rule the
     *  customer surface follows: don't confirm it exists. */
    private CustomerOrder requireForMerchant(Merchant merchant, UUID orderId) {
        return orders.findById(orderId)
            .filter(o -> o.getMerchantId().equals(merchant.getId()))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such order"));
    }

    private CustomerOrder requireForCourier(UUID courierUserId, UUID orderId) {
        return orders.findById(orderId)
            .filter(o -> courierUserId.equals(o.getCourierUserId()))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such order"));
    }

    private String merchantName(UUID merchantId) {
        return merchants.findById(merchantId).map(Merchant::getName).orElse("Restaurant");
    }

    /** What dispatch knows about the bike or the scooter — "E-bike", "Scooter ·
     *  Honda" — falling back to the bare category for a courier on foot. */
    private static String vehicleLabel(Assignment assignment) {
        String label = assignment.vehicle().label();
        if (label != null && !label.isBlank()) return label;
        return assignment.category() == null ? "" : friendly(assignment.category().name());
    }

    private static String friendly(String constant) {
        return constant.charAt(0) + constant.substring(1).toLowerCase();
    }

    private static String displayName(ProfileDto profile) {
        String name = profile.displayName();
        return name == null || name.isBlank() ? "@" + profile.handle() : name;
    }

    // MARK: Mapping

    private MerchantOrderDto toMerchantOrderDto(CustomerOrder order) {
        return new MerchantOrderDto(
            order.getId(),
            order.getStatus().name(),
            order.getLines().stream()
                .map(l -> new OrderLineDto(l.getMenuItemId(), l.getName(),
                    l.getUnitPriceCents(), l.getQty()))
                .toList(),
            order.getSubtotalCents(), order.getDiscountCents(), order.getCurrency(),
            payments.merchantEarningsOn(order),
            order.getNote(),
            order.getAddressLabel(),
            order.getCourierName(),
            order.getCourierSearch().name(),
            order.getPrepMinutes() == null ? 0 : order.getPrepMinutes(),
            order.getCancelReason(),
            // The kitchen's copy of the pickup code, and the only place it is
            // returned. The delivery PIN is deliberately not here: a restaurant
            // has no business knowing the number that confirms the food reached
            // somebody's door.
            order.getPickupCode(),
            order.getPlacedAt(), order.getAcceptedAt(), order.getReadyAt(),
            order.getStatusChangedAt());
    }

    /**
     * What the courier's phone shows. Two addresses and two names, and
     * deliberately nothing else about the customer: a courier needs to find a
     * door, not to know who lives behind it.
     *
     * <p>Neither handoff code is on it, which is the entire point of them. What
     * M2 adds here is a conversation id — a way to reach the person waiting,
     * which is the one thing a courier at a wrong door actually needs.
     */
    private CourierJobDto toCourierJobDto(CustomerOrder order) {
        return toCourierJobDto(order, merchants.findById(order.getMerchantId()).orElse(null));
    }

    private CourierJobDto toCourierJobDto(CustomerOrder order, Merchant merchant) {
        int items = order.getLines().stream().mapToInt(OrderLine::getQty).sum();
        return new CourierJobDto(
            order.getId(),
            order.getStatus().name(),
            merchant == null ? "Restaurant" : merchant.getName(),
            merchant == null ? null : merchant.getLatitude(),
            merchant == null ? null : merchant.getLongitude(),
            order.getAddressLabel(), order.getAddressLine(), order.getAddressNote(),
            order.getAddressLatitude(), order.getAddressLongitude(),
            items, order.getNote(),
            // How they want it handed over — an instruction the customer gave,
            // not one of the two secrets. Withholding it would have the app
            // quietly dropping "leave it at the door" on the way to the person
            // standing at it.
            order.getHandoffMode().name(),
            // What this delivery pays them, which is the number a courier
            // decides by — the fee plus whatever was tipped up front.
            order.getDeliveryFeeCents() + order.getTipCents(), order.getCurrency(),
            order.getConversationId(),
            order.getReadyAt(), order.getPickedUpAt(), order.getStatusChangedAt());
    }
}
