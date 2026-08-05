package com.gojogo.delivery.internal;

import com.gojogo.delivery.OrderStatusChanged;
import com.gojogo.media.MediaDocumentApi;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Complaints about delivered orders, and the money that goes back (Phase 4 M6,
 * SPECS §5).
 *
 * <p><b>The gap this closes has been open since 2e M3 shipped the wallet.</b>
 * Cancelling before delivery releases the hold; after delivery there was
 * nothing at all — the escrow is empty, the money is split three ways, and no
 * endpoint in the system could move any of it back. Every milestone since has
 * carried "disputes: not built" in its own deferred list, and the proof photo
 * M2 added is evidence <em>for</em> exactly this.
 *
 * <p><b>Resolution is a human act, and the code is built to keep it one.</b>
 * Nothing here decides anything: no auto-refund under a threshold, no
 * escalation on a timer, no scoring. It computes what each party actually
 * received for the order, refuses anything that exceeds it, and records who
 * decided. A refund that a rule made is a refund nobody has to justify, and the
 * failure mode of that is discovered a quarter later in the revenue line.
 */
@Service
class DisputeService {

    private static final Logger log = LoggerFactory.getLogger(DisputeService.class);

    /** Dispute photos share the private prefix with the drop-off proof, in
     *  their own folder — the same posture, and a folder apart because they are
     *  evidence in opposite directions. */
    private static final String PHOTO_FOLDER = "delivery-dispute";
    private static final String PHOTO_CONTENT_TYPE = "image/jpeg";

    private final DisputeRepository disputes;
    private final OrderRepository orders;
    private final MerchantRepository merchants;
    private final OrderPayments payments;
    private final DeliveryPolicy policy;
    private final MediaDocumentApi privateMedia;
    private final ApplicationEventPublisher events;

    DisputeService(DisputeRepository disputes, OrderRepository orders,
                   MerchantRepository merchants, OrderPayments payments,
                   DeliveryPolicy policy, MediaDocumentApi privateMedia,
                   ApplicationEventPublisher events) {
        this.disputes = disputes;
        this.orders = orders;
        this.merchants = merchants;
        this.payments = payments;
        this.policy = policy;
        this.privateMedia = privateMedia;
        this.events = events;
    }

    // MARK: The customer's side

    /**
     * Files a complaint about a delivered order.
     *
     * <p>The window is short and configured (24h), and it is measured from
     * delivery rather than from placement: a scheduled order placed on Monday
     * for Friday would otherwise arrive with its own complaint window already
     * expired.
     */
    @Transactional
    DisputeDto file(UUID me, UUID orderId, FileDisputeRequest request) {
        CustomerOrder order = requireOrder(me, orderId);
        if (order.getStatus() != OrderStatus.DELIVERED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                order.getStatus() == OrderStatus.CANCELLED
                    ? "That order was cancelled — nothing was charged for it"
                    : "You can report a problem once your order has arrived");
        }
        OffsetDateTime closed = order.getClosedAt();
        if (closed != null
            && closed.plusHours(policy.disputeWindowHours()).isBefore(OffsetDateTime.now())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That order is too old to report a problem with");
        }
        // One per order, and the reason is not tidiness: two open disputes about
        // one order is two operators refunding the same missing pizza.
        if (disputes.existsByOrderId(orderId)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "You've already reported a problem with this order");
        }
        SubOrder slice = resolveSlice(order, request.subOrderId());
        Dispute dispute = new Dispute(order, slice == null ? null : slice.getId(),
            DisputeReason.parse(request.reason()), request.note());
        dispute.claim(claimedItems(order, slice, request.items()));
        Dispute saved = disputes.save(dispute);
        log.info("Dispute {} filed on order {} ({}), claiming {}",
            saved.getId(), orderId, saved.getReason(), saved.getClaimedCents());
        return toDto(saved);
    }

    @Transactional(readOnly = true)
    DisputeDto mine(UUID me, UUID orderId) {
        requireOrder(me, orderId);
        return disputes.findByOrderId(orderId).map(this::toDto).orElse(null);
    }

    /**
     * A presigned PUT for a photo of what arrived.
     *
     * <p>Same shape as the courier's proof photo and for the same reasons: the
     * server mints the key and stamps it on the row in one transaction, so no
     * endpoint anywhere accepts a client-supplied key and there is no prefix
     * check to get wrong. Capped in number, because the upload is free to the
     * client and the bucket is not.
     */
    @Transactional
    ProofUploadDto photoUpload(UUID me, UUID orderId) {
        requireOrder(me, orderId);
        Dispute dispute = disputes.findByOrderId(orderId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Report the problem first"));
        if (!dispute.getState().isOpen()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That report has already been resolved");
        }
        if (dispute.getPhotoKeys().size() >= policy.disputeMaxPhotos()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "You can add up to " + policy.disputeMaxPhotos() + " photos");
        }
        MediaDocumentApi.DocumentUpload upload =
            privateMedia.presignDocumentUpload(me, PHOTO_FOLDER, PHOTO_CONTENT_TYPE);
        dispute.photographedAt(upload.objectKey());
        return new ProofUploadDto(upload.uploadUrl(), upload.objectKey(),
            upload.contentType(), upload.expiresSeconds());
    }

    // MARK: The operator's side

    @Transactional(readOnly = true)
    List<AdminDisputeDto> queue(String state, int limit) {
        DisputeState wanted = state == null || state.isBlank() ? null
            : DisputeState.valueOf(state.trim().toUpperCase());
        List<Dispute> rows = wanted == null
            ? disputes.openFirst(PageRequest.of(0, Math.clamp(limit, 1, 100)))
            : disputes.byState(wanted, PageRequest.of(0, Math.clamp(limit, 1, 100)));
        return rows.stream().map(this::toAdminDto).toList();
    }

    @Transactional(readOnly = true)
    AdminDisputeDto get(UUID disputeId) {
        return toAdminDto(require(disputeId));
    }

    /**
     * Refuses a dispute, in words the customer will read.
     *
     * <p>A note is required, which is the whole of what separates this from
     * letting a dispute go quiet. "No" is an answer; silence is a queue item
     * somebody chases forever.
     */
    @Transactional
    AdminDisputeDto reject(UUID disputeId, String note, String actor) {
        Dispute dispute = requireOpen(disputeId);
        dispute.rejected(note, actor, OffsetDateTime.now());
        announce(dispute);
        log.info("Dispute {} rejected by {}", disputeId, actor);
        return toAdminDto(dispute);
    }

    /**
     * Sends money back, out of a named party's earnings on this order.
     *
     * <p>Three refusals, and each one is a number the operator is told rather
     * than a silent clamp. **Over what that party received** for this order —
     * taking one order's dispute out of another order's earnings is how a
     * restaurant finds a refund it was never shown. **Over what is left of the
     * order** across every refund on it, so an order cannot give back more than
     * it took. And **over what the payer can actually cover**, because merchant
     * and user accounts cannot go negative: a kitchen that has already paid out
     * genuinely cannot fund this, and the honest answer is to say so and let a
     * person decide who absorbs it.
     */
    @Transactional
    AdminDisputeDto refund(UUID disputeId, int amountCents, String rawPayer,
                           String note, String actor) {
        Dispute dispute = requireOpen(disputeId);
        CustomerOrder order = dispute.getOrder();
        if (amountCents <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "A refund of nothing is a rejection — reject it instead");
        }
        DisputePayer payer = DisputePayer.parse(rawPayer, dispute.getReason().suggestedPayer());
        SubOrder slice = dispute.getSubOrderId() == null ? null
            : order.getSubOrders().stream()
                .filter(s -> dispute.getSubOrderId().equals(s.getId()))
                .findFirst().orElse(null);

        if (payer == DisputePayer.MERCHANT && slice == null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "This report isn't about one restaurant — refund from the courier "
                    + "or the platform, or ask the customer which kitchen it was");
        }
        if (payer == DisputePayer.COURIER && order.isPickup()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Nobody delivered this one — the customer collected it");
        }

        long received = payments.receivedOnOrder(order, payer, slice);
        if (amountCents > received) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That's more than the " + payerWord(payer) + " was paid for this order ("
                    + money(received) + ")");
        }
        int alreadyRefunded = disputes.refundedOnOrder(order.getId());
        if (alreadyRefunded + amountCents > order.getTotalCents()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That's more than the customer paid for this order ("
                    + money(order.getTotalCents() - alreadyRefunded) + " left)");
        }

        // Refused with a number rather than the ledger's own exception, which
        // the global handler would turn into a 402 — a status about the
        // *caller's* wallet, and the caller here is an operator.
        long payerBalance = payments.availableForPayer(order, payer, slice);
        if (amountCents > payerBalance) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "The " + payerWord(payer) + " only has " + money(payerBalance)
                    + " left — refund a smaller amount, or take it from the platform");
        }

        payments.refundDispute(order, dispute.getId(), payer, slice, amountCents);
        dispute.refunded(amountCents, payer, note, actor, OffsetDateTime.now());
        announce(dispute);
        log.info("Dispute {} refunded {} from {} by {}", disputeId, amountCents, payer, actor);
        return toAdminDto(dispute);
    }

    /**
     * Tells the customer their complaint was answered.
     *
     * <p>{@code DISPUTE_RESOLVED} is a push-only word and not a seventh order
     * status — the third of them, after {@code SUB_CANCELLED} and
     * {@code READY_FOR_PICKUP}, and for the same reason every time: the order
     * has not moved. A client that has never heard it drops it in the default
     * arm and stays quiet.
     */
    private void announce(Dispute dispute) {
        CustomerOrder order = dispute.getOrder();
        // Zero rather than the refund: that field is minutes everywhere else,
        // and a number that means one thing on one arm is a number somebody
        // renders as "450 min away" eventually. The amount is on the order.
        events.publishEvent(new OrderStatusChanged(order.getId(), order.getUserId(),
            merchantName(order, dispute), "DISPUTE_RESOLVED", 0, order.isPickup()));
    }

    // MARK: Reads and helpers

    private CustomerOrder requireOrder(UUID me, UUID orderId) {
        return orders.findById(orderId)
            .filter(o -> o.getUserId().equals(me))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such order"));
    }

    private Dispute require(UUID disputeId) {
        return disputes.findById(disputeId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such report"));
    }

    private Dispute requireOpen(UUID disputeId) {
        Dispute dispute = require(disputeId);
        if (!dispute.getState().isOpen()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That report has already been resolved");
        }
        return dispute;
    }

    /** The kitchen named, proven to be on this order. */
    private static SubOrder resolveSlice(CustomerOrder order, UUID subOrderId) {
        if (subOrderId == null) return null;
        return order.getSubOrders().stream()
            .filter(s -> subOrderId.equals(s.getId()))
            .findFirst()
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such part of this order"));
    }

    /**
     * Prices the claim off the order's own lines.
     *
     * <p>The client sends item ids and quantities, never amounts — the same
     * rule checkout follows, and for the same reason: a claim whose value the
     * client chose is a claim the client can inflate. A quantity above what was
     * actually ordered is clamped rather than refused, because somebody
     * reporting three missing drinks on an order of two has made a mistake worth
     * correcting, not a request worth failing.
     */
    private static List<Dispute.DisputedItem> claimedItems(CustomerOrder order, SubOrder slice,
                                                           List<DisputedItemRequest> requested) {
        if (requested == null || requested.isEmpty()) return List.of();
        Map<UUID, OrderLine> byItem = order.getLines().stream()
            .filter(line -> slice == null || line.belongsTo(slice))
            .collect(Collectors.toMap(OrderLine::getMenuItemId, Function.identity(),
                (first, second) -> first));
        List<Dispute.DisputedItem> claimed = new ArrayList<>();
        for (DisputedItemRequest item : requested) {
            OrderLine line = byItem.get(item.menuItemId());
            if (line == null) continue;
            claimed.add(new Dispute.DisputedItem(line.getMenuItemId(), line.getName(),
                line.getUnitPriceCents(), Math.clamp(item.qty(), 1, line.getQty())));
        }
        return claimed;
    }

    private String merchantName(CustomerOrder order, Dispute dispute) {
        UUID merchantId = dispute.getSubOrderId() == null
            ? order.getSubOrders().stream().findFirst().map(SubOrder::getMerchantId).orElse(null)
            : order.getSubOrders().stream()
                .filter(s -> dispute.getSubOrderId().equals(s.getId()))
                .findFirst().map(SubOrder::getMerchantId).orElse(null);
        if (merchantId == null) return "Restaurant";
        return merchants.findById(merchantId).map(Merchant::getName).orElse("Restaurant");
    }

    private static String payerWord(DisputePayer payer) {
        return switch (payer) {
            case MERCHANT -> "restaurant";
            case COURIER -> "courier";
            case PLATFORM -> "platform";
        };
    }

    private static String money(long cents) {
        return "%d.%02d".formatted(cents / 100, Math.abs(cents % 100));
    }

    private DisputeDto toDto(Dispute dispute) {
        return new DisputeDto(dispute.getId(), dispute.getSubOrderId(),
            dispute.getReason().name(), dispute.getNote(), dispute.getState().name(),
            dispute.getClaimedCents(), dispute.getRefundCents(),
            dispute.getResolutionNote(), dispute.getPhotoKeys().size(),
            dispute.getItems().stream()
                .map(item -> new DisputedItemDto(item.getMenuItemId(), item.getName(),
                    item.getUnitPriceCents(), item.getQty()))
                .toList(),
            dispute.getCreatedAt(), dispute.getResolvedAt());
    }

    /**
     * The operator's view, which carries what the customer's cannot: what each
     * party was actually paid, so the person deciding is not doing arithmetic
     * off a receipt in another tab.
     */
    private AdminDisputeDto toAdminDto(Dispute dispute) {
        CustomerOrder order = dispute.getOrder();
        SubOrder slice = dispute.getSubOrderId() == null ? null
            : order.getSubOrders().stream()
                .filter(s -> dispute.getSubOrderId().equals(s.getId()))
                .findFirst().orElse(null);
        return new AdminDisputeDto(toDto(dispute), order.getId(), dispute.getUserId(),
            merchantName(order, dispute), order.getTotalCents(), order.getCurrency(),
            order.getFulfilmentKind().name(),
            dispute.getReason().suggestedPayer().name(),
            payments.receivedOnOrder(order, DisputePayer.MERCHANT, slice),
            payments.receivedOnOrder(order, DisputePayer.COURIER, slice),
            payments.receivedOnOrder(order, DisputePayer.PLATFORM, slice),
            disputes.refundedOnOrder(order.getId()),
            // Signed links minted per read, never the keys — the same rule the
            // proof photo follows, for a picture somebody sent us of their
            // dinner and their kitchen table.
            dispute.getPhotoKeys().stream().map(this::signed).filter(java.util.Objects::nonNull)
                .toList(),
            order.getProofPhotoKey() == null ? null : signed(order.getProofPhotoKey()),
            dispute.getResolvedBy(), order.getStatusChangedAt());
    }

    private String signed(String objectKey) {
        try {
            return privateMedia.presignDocumentRead(objectKey);
        } catch (RuntimeException mediaIsHavingAMoment) {
            log.warn("Couldn't sign dispute photo {}: {}", objectKey,
                mediaIsHavingAMoment.toString());
            return null;
        }
    }
}
