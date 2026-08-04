package com.gojogo.delivery.internal;

import com.gojogo.delivery.OrderStatusChanged;
import com.gojogo.dispatch.Assignment;
import com.gojogo.dispatch.DispatchApi;
import com.gojogo.dispatch.DispatchRequest;
import com.gojogo.dispatch.JobKind;
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
 * wherever a timeline said it should be. Every transition below is caused by
 * somebody — a restaurant accepting, a courier accepting, a courier picking
 * food up, a courier handing it over.
 *
 * <p><b>Phase 4 M3 makes the kitchen's half per-merchant.</b> An order can span
 * kitchens, so accept / reject / ready act on a <em>sub-order</em>, each kitchen
 * mints its own pickup code, and the courier proves every counter separately.
 * The parent keeps the six statuses and the one courier: CONFIRMED until the
 * first kitchen says yes, DELIVERING once the last bag is in hand.
 *
 * <p><b>The courier trigger waits for the slowest kitchen.</b> The search opens
 * only once every sub-order is answered — a kitchen still deciding could push
 * the whole order's timing — and starts at {@code max(readyAt) − pickupLead}:
 * {@link DispatchRequest#startAfter}, exactly as M1 used it, with the max over
 * kitchens instead of one kitchen's clock.
 *
 * <p><b>Phase 4 M2's handoff evidence is unchanged in kind.</b> A pickup is
 * backed by a code only that counter can show — now one per counter — and the
 * handoff by a PIN only the customer knows, a photo, or an explicit choice to
 * need neither. A failed handoff still leaves the order in {@code DELIVERING},
 * because that is exactly what it is: the courier still has the food.
 */
@Service
class OrderFulfilmentService {

    private static final Logger log = LoggerFactory.getLogger(OrderFulfilmentService.class);

    /** What a kitchen is looking at: their slices not yet finished. */
    private static final Set<SubOrderStatus> LIVE_SLICES = EnumSet.of(SubOrderStatus.CONFIRMED,
        SubOrderStatus.PREPARING, SubOrderStatus.COLLECTED);

    private static final Set<SubOrderStatus> FINISHED_SLICES =
        EnumSet.of(SubOrderStatus.DELIVERED, SubOrderStatus.CANCELLED);

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
    private final SubOrderRepository subOrders;
    private final MerchantRepository merchants;
    private final OrderPayments payments;
    private final DeliveryPolicy policy;
    private final DispatchApi dispatch;
    private final ProfileApi profiles;
    private final MessagingApi messaging;
    private final MediaDocumentApi privateMedia;
    private final ApplicationEventPublisher events;

    OrderFulfilmentService(OrderRepository orders, SubOrderRepository subOrders,
                           MerchantRepository merchants,
                           OrderPayments payments, DeliveryPolicy policy,
                           DispatchApi dispatch, ProfileApi profiles,
                           MessagingApi messaging, MediaDocumentApi privateMedia,
                           ApplicationEventPublisher events) {
        this.orders = orders;
        this.subOrders = subOrders;
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

    /** The live queue, oldest first — a kitchen works in the order things
     *  arrived. Since Phase 4 M3 each row is this kitchen's own slice, and says
     *  nothing about the other merchants on the same order. */
    @Transactional(readOnly = true)
    List<MerchantOrderDto> queue(UUID ownerId) {
        Merchant merchant = requireMine(ownerId);
        return subOrders.queueFor(merchant.getId(), LIVE_SLICES)
            .stream().map(this::toMerchantOrderDto).toList();
    }

    @Transactional(readOnly = true)
    List<MerchantOrderDto> recent(UUID ownerId, int limit) {
        Merchant merchant = requireMine(ownerId);
        return subOrders.historyFor(merchant.getId(), FINISHED_SLICES,
                PageRequest.of(0, Math.clamp(limit, 1, 50)))
            .stream().map(this::toMerchantOrderDto).toList();
    }

    /**
     * The restaurant takes their slice and says how long they need.
     *
     * <p>The prep estimate is the load-bearing part, and it is why this is not a
     * bare "accept" button: it is the only thing in the system that knows when
     * this kitchen's food will be ready, and the courier search, the customer's
     * countdown and the courier's arrival are all timed to the <em>latest</em>
     * of these across the order. A missing or absurd number falls back to the
     * configured default rather than failing: an accept that can be rejected by
     * validation is an accept somebody in a kitchen does not make.
     *
     * <p><b>This kitchen's pickup code is minted here</b> — one per counter
     * since M3, because a courier collecting three bags proves each counter
     * separately. The delivery PIN is minted on the first accept: there is one
     * door however many kitchens, and by the time anybody could need either, the
     * screen that shows it has it.
     */
    @Transactional
    MerchantOrderDto accept(UUID ownerId, UUID subOrderId, Integer requestedPrepMinutes) {
        Merchant merchant = requireMine(ownerId);
        SubOrder sub = requireSlice(merchant, subOrderId);
        CustomerOrder order = sub.getOrder();
        if (order.getStatus().isTerminal() || sub.getStatus() != SubOrderStatus.CONFIRMED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                sub.getStatus() == SubOrderStatus.CANCELLED || order.getStatus().isTerminal()
                    ? "That order was cancelled"
                    : "You've already accepted that order");
        }
        int prep = requestedPrepMinutes == null || requestedPrepMinutes <= 0
            ? defaultPrepFor(order, merchant)
            : Math.min(requestedPrepMinutes, policy.maxPrepMinutes());

        OffsetDateTime now = OffsetDateTime.now();
        sub.accepted(now, prep);
        int digits = policy.handoffCodeLength();
        // The same code either way — it is minted here, at this counter, for
        // this slice, and what changes with the fulfilment kind is only who
        // reads it and who types it. The delivery PIN is not minted for a
        // collection: there is no door, and a number nobody will ever be asked
        // for is a number sitting on a screen inviting somebody to read it out.
        sub.mintPickupCode(HandoffCodes.numeric(digits));
        if (!order.isPickup()) {
            order.mintDeliveryPin(HandoffCodes.numeric(digits));
        }
        boolean firstAccept = order.getStatus() == OrderStatus.CONFIRMED;
        if (firstAccept) {
            order.moveTo(OrderStatus.PREPARING, now);
        }
        retime(order);
        // Flushed before dispatch is asked, so an order that fails to save never
        // puts a job in front of a courier.
        orders.flush();
        maybeOpenCourierSearch(order);
        if (firstAccept) {
            publish(order, merchant.getName());
        }
        return toMerchantOrderDto(sub);
    }

    /**
     * The restaurant says no to their slice. Only before they have accepted —
     * once a kitchen has started, "reject" is a cancellation with food already
     * made, which is a dispute (SPECS §5) rather than a button.
     */
    @Transactional
    MerchantOrderDto reject(UUID ownerId, UUID subOrderId, String reason) {
        Merchant merchant = requireMine(ownerId);
        SubOrder sub = requireSlice(merchant, subOrderId);
        if (sub.getStatus() != SubOrderStatus.CONFIRMED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Too late to turn that one down");
        }
        cancelSubOrder(sub.getOrder(), sub, reason == null || reason.isBlank()
            ? "The restaurant couldn't take this order" : reason.trim());
        return toMerchantOrderDto(sub);
    }

    /**
     * This kitchen's food is ready — sooner or later than they guessed.
     *
     * <p>Worth having even though the courier has usually been found by now:
     * the order's {@code readyAt} is the latest kitchen's, and the pickup time
     * on the courier's screen is drawn from it. It does not change any status,
     * because "cooked" is not a stage the customer can act on — their food is
     * still coming, and the screen still says so.
     *
     * <p><b>For a collection it is the other way round, and that is what Phase 4
     * M4 added here.</b> The customer <em>is</em> the person who has to act, so
     * this tap is the difference between an estimate and a fact, and it is the
     * one push a pickup order genuinely needs. {@code READY_FOR_PICKUP} is a
     * push-only word rather than a seventh status — the same shape M3 gave
     * {@code SUB_CANCELLED}: the parent has not moved, {@code notifications}
     * turns it into "your order is ready to collect", and a client that has
     * never heard the word drops it in the default arm.
     */
    @Transactional
    MerchantOrderDto markReady(UUID ownerId, UUID subOrderId) {
        Merchant merchant = requireMine(ownerId);
        SubOrder sub = requireSlice(merchant, subOrderId);
        if (sub.getStatus() != SubOrderStatus.PREPARING) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That order isn't being prepared");
        }
        CustomerOrder order = sub.getOrder();
        boolean alreadyAnnounced = sub.getReadyMarkedAt() != null;
        sub.readyNow(OffsetDateTime.now());
        retime(order);
        // Once per kitchen, however many times somebody taps it: a second push
        // saying the same thing reads as a second order.
        if (order.isPickup() && !alreadyAnnounced) {
            events.publishEvent(new OrderStatusChanged(order.getId(), order.getUserId(),
                merchant.getName(), "READY_FOR_PICKUP", 0, true));
        }
        return toMerchantOrderDto(sub);
    }

    /**
     * The customer is at the counter with their code, and the kitchen types it.
     *
     * <p><b>The direction is the opposite of the courier's pickup, and that is
     * the rule rather than an exception to it.</b> M2 reversed SPECS §5 for a
     * delivery because the courier is the one who cannot be paid until the step
     * is done; here the payee is the person standing behind the counter — a
     * collection settles the order and pays the kitchen — so the same reasoning
     * lands on the merchant typing, which is what §5 asked for in the first
     * place. Underneath both: <em>the code is displayed to the party that does
     * not type it, and typed by the party who is paid for completing the
     * step.</em>
     *
     * <p>A wrong code is a 200 carrying the message, like both handoff verbs,
     * and for the mechanical reason as much as the human one — a thrown
     * exception would roll back the very thing it was recording. Attempts are
     * <b>not</b> counted here: the customer is standing right there with the
     * code on their screen, so this is a check and not a gate, and a kitchen
     * locked out of handing over food they have already made is by far the
     * worse failure. That is the M2 asymmetry, applied at the same kind of
     * counter it was written for.
     *
     * <p>The last live slice collected finishes the order: DELIVERED (the six
     * words are unchanged, and a client renders "Collected" from the fulfilment
     * kind), and settlement runs with the courier's two lines at zero, which
     * the ledger skips because a zero fee is not an entry.
     */
    @Transactional
    CollectionResultDto collected(UUID ownerId, UUID subOrderId, String typedCode) {
        Merchant merchant = requireMine(ownerId);
        SubOrder sub = requireSlice(merchant, subOrderId);
        CustomerOrder order = sub.getOrder();
        if (!order.isPickup()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That order is being delivered — the courier collects it");
        }
        if (sub.getStatus() != SubOrderStatus.PREPARING) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                sub.getStatus() == SubOrderStatus.CONFIRMED
                    ? "Accept the order first"
                    : "That order has already been collected");
        }
        String typed = HandoffCodes.digitsOf(typedCode);
        if (!typed.equals(sub.getPickupCode()) || typed.isEmpty()) {
            // Never says how wrong it was: "one digit off" is a hint, and a hint
            // is a shorter guess list. The empty case is folded in here rather
            // than given its own message, because a blank submission at a
            // counter is a mis-tap and not a situation — unlike the doorstep,
            // where it is the only honest way to reach the fallback.
            return new CollectionResultDto(false,
                "That code doesn't match — check the customer's order screen",
                -1, toMerchantOrderDto(sub));
        }
        OffsetDateTime now = OffsetDateTime.now();
        sub.collected(now);
        boolean anyLeft = order.getSubOrders().stream()
            .anyMatch(s -> s.getStatus() == SubOrderStatus.CONFIRMED
                || s.getStatus() == SubOrderStatus.PREPARING);
        if (!anyLeft) {
            finishCollectedOrder(order, now);
            return new CollectionResultDto(true, "Collected", -1, toMerchantOrderDto(sub));
        }
        return new CollectionResultDto(true, "Collected — the customer has another counter to visit",
            -1, toMerchantOrderDto(sub));
    }

    /**
     * Every bag collected: the order is finished and the money moves.
     *
     * <p>Straight to DELIVERED rather than through DELIVERING, because there is
     * nothing between a counter and the person at it. Dispatch is deliberately
     * not told anything — it was never asked for this order, and
     * {@code complete} on a job that does not exist is a question with no
     * answer rather than a no-op worth relying on.
     */
    private void finishCollectedOrder(CustomerOrder order, OffsetDateTime at) {
        Map<UUID, Merchant> byId = merchantsOf(List.of(order));
        order.pickedUp(at);
        order.moveTo(OrderStatus.DELIVERED, at);
        order.getSubOrders().stream()
            .filter(s -> s.getStatus() != SubOrderStatus.CANCELLED)
            .forEach(SubOrder::deliveredWithParent);
        payments.settle(order, byId.entrySet().stream()
            .collect(Collectors.toMap(Map.Entry::getKey, e -> e.getValue().getName())));
        publish(order, primaryMerchantName(order));
    }

    // MARK: Order-level clockwork

    /**
     * Re-derives the parent's clock from its kitchens: ready when the last one
     * still cooking is, at the door a dropoff after that. Collected and
     * cancelled slices no longer bind — food already in the bag does not push
     * the ETA.
     */
    private void retime(CustomerOrder order) {
        OffsetDateTime latest = order.getSubOrders().stream()
            .filter(s -> s.getStatus() == SubOrderStatus.PREPARING)
            .map(SubOrder::getReadyAt)
            .filter(java.util.Objects::nonNull)
            .max(OffsetDateTime::compareTo)
            .orElse(order.getReadyAt());
        if (latest != null) {
            // A collection is ready when it is ready — no journey to add.
            // Adding the dropoff anyway would put a countdown on the
            // customer's screen that runs fifteen minutes past the moment the
            // food is sitting on the counter going cold.
            order.retime(latest, order.isPickup()
                ? latest
                : latest.plusMinutes(policy.dropoffMinutes()));
        }
    }

    /**
     * How long this kitchen takes when they do not say — their own collection
     * time for a pickup, the configured default otherwise. A merchant who has
     * set no pickup time is not one to invent a faster number for, so it falls
     * back to the shared pickup default rather than to their delivery ETA,
     * which has a courier's journey inside it.
     */
    private int defaultPrepFor(CustomerOrder order, Merchant merchant) {
        if (!order.isPickup()) return policy.defaultPrepMinutes();
        return merchant.getPickupPrepMinutes() == null
            ? policy.defaultPickupPrepMinutes()
            : Math.clamp(merchant.getPickupPrepMinutes(), 1, policy.maxPrepMinutes());
    }

    /**
     * Opens the courier search once every kitchen has answered, timed to the
     * slowest of them.
     *
     * <p>Not on the first accept: a kitchen still deciding could add twenty
     * minutes to the order, and a courier searched for on the fast kitchen's
     * clock stands at a counter waiting for the slow one. A slice that gets
     * rejected instead of accepted still counts as an answer — the search opens
     * for whatever survived.
     *
     * <p>Never throws into the accept that called it. A restaurant's accept is
     * not the right transaction to fail because dispatch had a bad moment — the
     * order is accepted, the kitchen is cooking, and an order with no search
     * running is visibly stuck rather than silently wrong: it stays
     * {@code SEARCHING = NONE} and reads as a failed search to everybody looking
     * at it.
     */
    private void maybeOpenCourierSearch(CustomerOrder order) {
        // Nobody is coming for a collection. This is the whole of what "no
        // dispatch" costs, and it is one line because the kind was modelled as
        // a kind rather than as a delivery with a courier who happens to be
        // nobody — that version would have had to teach dispatch about an
        // order it must never be offered.
        if (order.isPickup()) {
            return;
        }
        if (order.getCourierSearch() != CourierSearch.NONE || order.getStatus().isTerminal()) {
            return;
        }
        if (!order.allSubOrdersAnswered()) {
            return;
        }
        List<SubOrder> cooking = order.getSubOrders().stream()
            .filter(s -> s.getStatus() == SubOrderStatus.PREPARING)
            .toList();
        if (cooking.isEmpty()) {
            return;
        }
        Merchant firstStop = merchants.findById(cooking.getFirst().getMerchantId()).orElse(null);
        if (firstStop == null) {
            order.noCourierFound();
            return;
        }
        String pickupName = cooking.size() == 1
            ? firstStop.getName()
            : firstStop.getName() + " + " + (cooking.size() - 1) + " more";
        try {
            dispatch.request(new DispatchRequest(JobKind.DELIVERY, order.getId(),
                com.gojogo.dispatch.WorkerKind.COURIER, policy.courierCategories(),
                order.getUserId(),
                firstStop.getLatitude(), firstStop.getLongitude(), pickupName,
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
        Merchant primary = primaryMerchant(order);
        openConversation(order, primary);
        publish(order, primary == null ? "Restaurant" : primary.getName());
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
        Map<UUID, Merchant> byId = merchantsOf(page);
        return page.stream().map(o -> toCourierJobDto(o, byId)).toList();
    }

    /**
     * They have a bag, and they can prove they were standing at its counter.
     *
     * <p>The proof is a code <b>that merchant's screen shows and the courier
     * types</b> — since Phase 4 M3 one code per kitchen, and the typed digits
     * are what say which counter this is: the code lands on the slice it was
     * minted for, so a courier cannot mark the far kitchen's bag collected from
     * the near kitchen's counter. The direction is still the reverse of SPECS
     * §5 and still deliberate: the party who must act is the party with the
     * incentive.
     *
     * <p><b>A wrong code here is never counted and never locks anybody out</b> —
     * the asymmetry with the delivery PIN is the point. At the counter the
     * merchant is standing right there; the code is a check rather than a gate.
     * {@code attemptsLeft} is {@code -1} on this endpoint to say "not counted".
     *
     * <p>The order stops being cancellable at the <em>first</em> collected bag;
     * the parent moves to DELIVERING at the last one.
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
        List<SubOrder> waiting = order.getSubOrders().stream()
            .filter(s -> s.getStatus() == SubOrderStatus.PREPARING)
            .toList();
        if (waiting.isEmpty()) {
            // Every surviving bag is already in hand — the status just hasn't
            // caught up, which the block below fixes.
            return advanceIfAllCollected(order);
        }

        String typed = HandoffCodes.digitsOf(typedCode);
        SubOrder collected;
        if (typed.isEmpty()) {
            // A blank code on the row is an order accepted before V38. It is
            // not a locked door: there is no code for anybody in that
            // restaurant to read out, so there is nothing to check and the
            // collect works as it did in M1. A migration must not lock a
            // courier out of food they are holding.
            collected = waiting.size() == 1 && waiting.getFirst().getPickupCode().isBlank()
                ? waiting.getFirst() : null;
            if (collected == null) {
                return refused(order, "Ask the restaurant for the pickup code", -1, false);
            }
        } else {
            // The digits say which counter this is. Never says how wrong a miss
            // was — "one digit off" is a hint, and a hint is a shorter guess
            // list.
            collected = waiting.stream()
                .filter(s -> typed.equals(s.getPickupCode()))
                .findFirst().orElse(null);
            if (collected == null) {
                return refused(order, "That code doesn't match — check the screen at the counter",
                    -1, false);
            }
        }
        collected.collected(OffsetDateTime.now());
        return advanceIfAllCollected(order);
    }

    /** Moves the parent once the last bag is in hand; otherwise reports the
     *  stop and how many are left. */
    private HandoffResultDto advanceIfAllCollected(CustomerOrder order) {
        long left = order.getSubOrders().stream()
            .filter(s -> s.getStatus() == SubOrderStatus.PREPARING)
            .count();
        if (left == 0) {
            OffsetDateTime now = OffsetDateTime.now();
            order.pickedUp(now);
            order.moveTo(OrderStatus.DELIVERING, now);
            publish(order, primaryMerchantName(order));
            return new HandoffResultDto(true, "Collected", -1, false, toCourierJobDto(order));
        }
        return new HandoffResultDto(true,
            left == 1 ? "Collected — 1 more pickup to go" : "Collected — " + left + " more pickups to go",
            -1, false, toCourierJobDto(order));
    }

    /**
     * Handed over. The one transition that moves money: the hold placed at
     * checkout is split between every surviving merchant, the platform and the
     * courier who carried it. Which is exactly why this is the handoff that is
     * verified and counted: everything upstream can be redone, and this one
     * pays somebody.
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

        Map<UUID, Merchant> byId = merchantsOf(List.of(order));
        order.moveTo(OrderStatus.DELIVERED, OffsetDateTime.now());
        order.getSubOrders().stream()
            .filter(s -> s.getStatus() != SubOrderStatus.CANCELLED)
            .forEach(SubOrder::deliveredWithParent);
        payments.settle(order, byId.entrySet().stream()
            .collect(Collectors.toMap(Map.Entry::getKey, e -> e.getValue().getName())));
        dispatch.complete(JobKind.DELIVERY, order.getId(), null);
        publish(order, primaryMerchantName(order));
        return new HandoffResultDto(true, "Delivered", attemptsLeft(order, max),
            unlocked, toCourierJobDto(order, byId));
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
        // like a broken upload and is actually a bad signature.
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
     * Slices nobody in a kitchen ever answered.
     *
     * <p>Per kitchen since Phase 4 M3, because "the restaurant didn't answer"
     * is a fact about one restaurant and must not time out the two that did:
     * the silent kitchen's slice is cancelled and refunded, and the order
     * carries on with whoever answered. Only when every slice has ended does
     * the order itself. The same query still catches whole orders stranded
     * before a kitchen ever saw them.
     */
    @Transactional(readOnly = true)
    List<UUID> unansweredSubOrderIds(int limit) {
        OffsetDateTime cutoff = OffsetDateTime.now().minusMinutes(policy.acceptTimeoutMinutes());
        return subOrders.unansweredIds(TERMINAL, cutoff, PageRequest.of(0, limit));
    }

    @Transactional
    void timeOut(UUID subOrderId) {
        SubOrder sub = subOrders.findById(subOrderId).orElse(null);
        if (sub == null || sub.getStatus() != SubOrderStatus.CONFIRMED
            || sub.getOrder().getStatus().isTerminal()) {
            return;
        }
        cancelSubOrder(sub.getOrder(), sub,
            "The restaurant didn't answer in time — you haven't been charged");
    }

    // MARK: Shared

    /**
     * Ends one kitchen's slice and gives its share back. If it was the last
     * live slice the whole order ends with it; otherwise the order re-times
     * around the kitchens that remain, and the courier search opens if this
     * was the answer it had been waiting on.
     */
    void cancelSubOrder(CustomerOrder order, SubOrder sub, String reason) {
        String merchantName = merchantName(sub.getMerchantId());
        sub.cancelledBecause(reason);
        boolean anyLeft = order.getSubOrders().stream()
            .anyMatch(s -> s.getStatus().isLive());
        if (!anyLeft) {
            // The last live slice ends the order, and the full release covers
            // this slice's share too — one movement, not a share plus a rump.
            cancel(order, reason);
            return;
        }
        payments.releaseSubOrder(order, sub, merchantName);
        retime(order);
        maybeOpenCourierSearch(order);
        // The parent's status hasn't moved, so this is its own word: the push
        // listener turns SUB_CANCELLED into "part of your order was refunded"
        // and clients that predate it drop it on the floor.
        events.publishEvent(new OrderStatusChanged(order.getId(), order.getUserId(),
            merchantName, "SUB_CANCELLED", Eta.minutesLeft(order), order.isPickup()));
    }

    /**
     * Ends an order and gives back whatever money is still held. Dispatch is
     * told whatever stage it had reached, and told nothing at all if it never
     * heard of this order — {@code cancel} is safe for a job that was never
     * requested, which is what lets this one method serve a rejection, a
     * timeout and a customer changing their mind.
     */
    void cancel(CustomerOrder order, String reason) {
        order.moveTo(OrderStatus.CANCELLED, OffsetDateTime.now());
        order.cancelledBecause(reason);
        order.getSubOrders().stream()
            .filter(s -> s.getStatus().isLive())
            .forEach(s -> s.cancelledBecause(reason));
        // Never the courier's fault: they are being stood down, not walking away.
        dispatch.cancel(JobKind.DELIVERY, order.getId(), false);
        payments.release(order);
        publish(order, primaryMerchantName(order));
    }

    private void publish(CustomerOrder order, String merchantName) {
        events.publishEvent(new OrderStatusChanged(order.getId(), order.getUserId(),
            merchantName, order.getStatus().name(), Eta.minutesLeft(order),
            order.isPickup()));
    }

    private Merchant requireMine(UUID ownerId) {
        return merchants.findFirstByOwnerId(ownerId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "You don't manage a restaurant"));
    }

    /** 404 rather than 403 for another restaurant's slice — the same rule the
     *  customer surface follows: don't confirm it exists. */
    private SubOrder requireSlice(Merchant merchant, UUID subOrderId) {
        return subOrders.findById(subOrderId)
            .filter(s -> s.getMerchantId().equals(merchant.getId()))
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

    /** The order's face for anything that wants one name: its first slice's
     *  restaurant. */
    private Merchant primaryMerchant(CustomerOrder order) {
        return order.getSubOrders().isEmpty() ? null
            : merchants.findById(order.getSubOrders().getFirst().getMerchantId()).orElse(null);
    }

    private String primaryMerchantName(CustomerOrder order) {
        Merchant primary = primaryMerchant(order);
        return primary == null ? "Restaurant" : primary.getName();
    }

    /** One query for every merchant these orders span. */
    private Map<UUID, Merchant> merchantsOf(List<CustomerOrder> page) {
        return merchants
            .findAllById(page.stream()
                .flatMap(o -> o.getSubOrders().stream())
                .map(SubOrder::getMerchantId)
                .collect(Collectors.toSet()))
            .stream().collect(Collectors.toMap(Merchant::getId, Function.identity()));
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

    /**
     * One kitchen's slice, in the order vocabulary that kitchen's screen has
     * always spoken. The slice's own states map onto the six words — a
     * COLLECTED slice reads as DELIVERING, "the courier has your bag" — so the
     * deployed app renders a multi-merchant order without a client release.
     */
    private MerchantOrderDto toMerchantOrderDto(SubOrder sub) {
        CustomerOrder order = sub.getOrder();
        String status = switch (sub.getStatus()) {
            case CONFIRMED -> OrderStatus.CONFIRMED.name();
            case PREPARING -> order.getStatus() == OrderStatus.COURIER_TO_RESTAURANT
                ? OrderStatus.COURIER_TO_RESTAURANT.name()
                : OrderStatus.PREPARING.name();
            // "The courier has your bag" for a delivery; for a collection the
            // bag has left with the person who ordered it, and as far as this
            // kitchen is concerned that is the end of it.
            case COLLECTED -> order.isPickup()
                ? OrderStatus.DELIVERED.name()
                : OrderStatus.DELIVERING.name();
            case DELIVERED -> OrderStatus.DELIVERED.name();
            case CANCELLED -> OrderStatus.CANCELLED.name();
        };
        return new MerchantOrderDto(
            sub.getId(),
            status,
            order.getLines().stream()
                .filter(l -> l.belongsTo(sub))
                .map(l -> new OrderLineDto(l.getMenuItemId(), l.getName(),
                    l.getUnitPriceCents(), l.getQty()))
                .toList(),
            sub.getSubtotalCents(), sub.getDiscountCents(), order.getCurrency(),
            payments.merchantEarningsOn(sub),
            order.getNote(),
            // "Collection" rather than a home the food is not going to. The
            // kitchen's screen has one line for where an order is headed, and
            // for a pickup the honest answer is that it is not headed anywhere.
            order.isPickup() ? "Collection" : order.getAddressLabel(),
            order.getCourierName(),
            order.getCourierSearch().name(),
            sub.getPrepMinutes() == null ? 0 : sub.getPrepMinutes(),
            sub.getCancelReason().isEmpty() ? order.getCancelReason() : sub.getCancelReason(),
            // The kitchen's copy of their own pickup code — and blank on a
            // collection, which is the inversion this milestone turns on. On a
            // delivery the kitchen shows it and the courier types it; on a
            // collection the customer shows it and the kitchen types it, so a
            // kitchen that could read it here could hand the food to nobody and
            // settle the order. The delivery PIN is on neither, as before.
            order.isPickup() ? "" : sub.getPickupCode(),
            order.getFulfilmentKind().name(),
            sub.getReadyMarkedAt() != null,
            order.getPlacedAt(), sub.getAcceptedAt(), sub.getReadyAt(),
            order.getStatusChangedAt());
    }

    /**
     * What the courier's phone shows. The addresses, the stops, and
     * deliberately nothing else about the customer: a courier needs to find a
     * door, not to know who lives behind it.
     *
     * <p>No pickup code and no PIN are on it, which is the entire point of
     * them. The single merchant fields carry the <em>next uncollected</em>
     * stop, so an older client's one-restaurant screen always points at the
     * right counter.
     */
    private CourierJobDto toCourierJobDto(CustomerOrder order) {
        return toCourierJobDto(order, merchantsOf(List.of(order)));
    }

    private CourierJobDto toCourierJobDto(CustomerOrder order, Map<UUID, Merchant> byId) {
        List<SubOrder> slices = order.getSubOrders().stream()
            .filter(s -> s.getStatus() != SubOrderStatus.CANCELLED)
            .toList();
        List<CourierStopDto> stops = slices.stream().map(sub -> {
            Merchant merchant = byId.get(sub.getMerchantId());
            return new CourierStopDto(sub.getId(),
                merchant == null ? "Restaurant" : merchant.getName(),
                merchant == null ? null : merchant.getLatitude(),
                merchant == null ? null : merchant.getLongitude(),
                itemsIn(order, sub),
                sub.getStatus() == SubOrderStatus.COLLECTED
                    || sub.getStatus() == SubOrderStatus.DELIVERED,
                sub.getReadyAt());
        }).toList();
        CourierStopDto target = stops.stream()
            .filter(stop -> !stop.collected())
            .findFirst()
            .orElse(stops.isEmpty() ? null : stops.getFirst());
        int items = stops.stream().mapToInt(CourierStopDto::itemCount).sum();
        int fees = slices.stream().mapToInt(SubOrder::getDeliveryFeeCents).sum();
        return new CourierJobDto(
            order.getId(),
            order.getStatus().name(),
            target == null ? "Restaurant" : target.merchantName(),
            target == null ? null : target.latitude(),
            target == null ? null : target.longitude(),
            order.getAddressLabel(), order.getAddressLine(), order.getAddressNote(),
            order.getAddressLatitude(), order.getAddressLongitude(),
            items, order.getNote(),
            // How they want it handed over — an instruction the customer gave,
            // not one of the secrets. Withholding it would have the app
            // quietly dropping "leave it at the door" on the way to the person
            // standing at it.
            order.getHandoffMode().name(),
            // What this delivery pays them, which is the number a courier
            // decides by — every stop's fee plus whatever was tipped up front.
            fees + order.getTipCents(), order.getCurrency(),
            order.getConversationId(),
            stops,
            order.getReadyAt(), order.getPickedUpAt(), order.getStatusChangedAt());
    }

    private static int itemsIn(CustomerOrder order, SubOrder sub) {
        return order.getLines().stream()
            .filter(l -> l.belongsTo(sub))
            .mapToInt(OrderLine::getQty)
            .sum();
    }
}
