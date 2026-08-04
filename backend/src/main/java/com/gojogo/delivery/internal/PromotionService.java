package com.gojogo.delivery.internal;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

/**
 * Promotions: choosing one, applying it, and letting a merchant run them.
 *
 * <p>Two ways one attaches to a basket. A <b>code</b> the customer typed, which
 * is refused loudly if it doesn't apply — someone who typed WELCOME10 and got
 * nothing deserves to be told why. Or an <b>automatic</b> promotion, where the
 * best qualifying one is applied silently; a customer who was never told about a
 * discount cannot be disappointed by which one they got, and picking the largest
 * is the only choice that never needs defending.
 */
@Service
class PromotionService {

    private final PromotionRepository promotions;
    private final PromotionRedemptionRepository redemptions;

    PromotionService(PromotionRepository promotions, PromotionRedemptionRepository redemptions) {
        this.promotions = promotions;
        this.redemptions = redemptions;
    }

    /**
     * The discount for this basket, and what caused it.
     *
     * @param code what the customer typed, or blank for "whatever applies"
     */
    @Transactional(readOnly = true)
    Applied resolve(UUID merchantId, UUID userId, String code,
                    int subtotalCents, int deliveryFeeCents) {
        OffsetDateTime now = OffsetDateTime.now();
        if (code != null && !code.isBlank()) {
            Promotion promotion = promotions
                .findByMerchantIdAndCodeIgnoreCase(merchantId, code.trim())
                .filter(found -> found.liveAt(now))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                    "That code isn't valid here"));
            if (exhaustedBy(promotion, userId)) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "You've already used that code");
            }
            int discount = promotion.discountFor(subtotalCents, deliveryFeeCents);
            if (discount <= 0) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                    promotion.getMinBasketCents() > subtotalCents
                        ? "Spend %s to use that code".formatted(display(promotion.getMinBasketCents()))
                        : "That code doesn't apply to this order");
            }
            return new Applied(promotion.getId(), promotion.getCode(), promotion.getLabel(), discount);
        }

        return promotions.findByMerchantIdAndActiveTrue(merchantId).stream()
            .filter(promotion -> promotion.getCode().isEmpty())
            .filter(promotion -> promotion.liveAt(now))
            .filter(promotion -> !exhaustedBy(promotion, userId))
            .map(promotion -> new Applied(promotion.getId(), "", promotion.getLabel(),
                promotion.discountFor(subtotalCents, deliveryFeeCents)))
            .filter(applied -> applied.discountCents() > 0)
            .max(Comparator.comparingInt(Applied::discountCents))
            .orElse(Applied.none());
    }

    /** Records that it was used. One row per (promotion, order) — a retried
     *  checkout must not count twice against someone's allowance, and an order
     *  spanning merchants may carry one promotion per kitchen. */
    @Transactional
    void redeem(Applied applied, UUID userId, UUID orderId) {
        if (applied.promotionId() == null || applied.discountCents() <= 0) return;
        if (redemptions.existsByPromotionIdAndOrderId(applied.promotionId(), orderId)) return;
        redemptions.save(new PromotionRedemption(applied.promotionId(), userId, orderId,
            applied.discountCents()));
    }

    private boolean exhaustedBy(Promotion promotion, UUID userId) {
        return promotion.getPerUserLimit() > 0
            && redemptions.countByPromotionIdAndUserId(promotion.getId(), userId)
               >= promotion.getPerUserLimit();
    }

    // MARK: The merchant's side

    @Transactional(readOnly = true)
    List<PromotionDto> forMerchant(UUID merchantId) {
        return promotions.findByMerchantIdOrderByCreatedAtDesc(merchantId).stream()
            .map(PromotionService::toDto)
            .toList();
    }

    /** What a customer could be offered here — active, in window, and worth
     *  something. Codes are included: a restaurant advertising a code wants it
     *  discoverable. */
    @Transactional(readOnly = true)
    List<PromotionDto> liveFor(UUID merchantId) {
        OffsetDateTime now = OffsetDateTime.now();
        return promotions.findByMerchantIdAndActiveTrue(merchantId).stream()
            .filter(promotion -> promotion.liveAt(now))
            .map(PromotionService::toDto)
            .toList();
    }

    @Transactional
    PromotionDto create(UUID merchantId, SavePromotionRequest request) {
        Promotion.Kind kind;
        try {
            kind = Promotion.Kind.valueOf(request.kind().toUpperCase());
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Kind must be PERCENT, FIXED or FREE_DELIVERY");
        }
        if (kind == Promotion.Kind.PERCENT && (request.valueBps() <= 0 || request.valueBps() > 10_000)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "A percentage promotion needs a percentage between 0 and 100");
        }
        if (kind == Promotion.Kind.FIXED && request.amountCents() <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "A fixed promotion needs an amount");
        }
        String code = request.code() == null || request.code().isBlank()
            ? null : request.code().trim().toUpperCase();
        if (code != null && promotions.findByMerchantIdAndCodeIgnoreCase(merchantId, code)
                .filter(Promotion::isActive).isPresent()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "You already have a live promotion with that code");
        }
        return toDto(promotions.save(new Promotion(merchantId, code, request.label(), kind,
            request.valueBps(), request.amountCents(), request.minBasketCents(),
            request.maxDiscountCents(), request.perUserLimit(),
            request.startsAt(), request.endsAt())));
    }

    /**
     * Ends a promotion rather than deleting it. Orders reference it, and a
     * campaign that vanishes takes its own results with it.
     */
    @Transactional
    void deactivate(UUID merchantId, UUID promotionId) {
        Promotion promotion = promotions.findById(promotionId)
            .filter(found -> found.getMerchantId().equals(merchantId))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such promotion"));
        promotion.deactivate();
    }

    private static PromotionDto toDto(Promotion promotion) {
        return new PromotionDto(promotion.getId(), promotion.getCode(), promotion.getLabel(),
            promotion.getKind().name(), promotion.getValueBps(), promotion.getAmountCents(),
            promotion.getMinBasketCents(), promotion.getMaxDiscountCents(),
            promotion.getPerUserLimit(), promotion.getStartsAt(), promotion.getEndsAt(),
            promotion.isActive());
    }

    private static String display(int cents) {
        return "%d.%02d".formatted(cents / 100, Math.abs(cents % 100));
    }

    /** The outcome of choosing a promotion for a basket. */
    record Applied(UUID promotionId, String code, String label, int discountCents) {

        static Applied none() {
            return new Applied(null, "", "", 0);
        }
    }
}
