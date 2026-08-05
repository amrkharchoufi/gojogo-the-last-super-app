package com.gojogo.economy.internal;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

/**
 * Resolves what a basket is worth less — SPECS §6's promotion shape, applied
 * server-side at pricing time and nowhere else.
 */
@Service
class ProductPromotionService {

    private final ProductPromotionRepository promotions;
    private final ProductPromotionRedemptionRepository redemptions;

    ProductPromotionService(ProductPromotionRepository promotions,
                            ProductPromotionRedemptionRepository redemptions) {
        this.promotions = promotions;
        this.redemptions = redemptions;
    }

    /** A resolved discount, ready to be priced in and recorded at placement. */
    record Applied(ProductPromotion promotion, int discountCents) {
    }

    /**
     * The best the basket qualifies for. A typed code that lands nowhere is
     * refused out loud (delivery M3's rule); an automatic promotion that
     * doesn't qualify is simply not applied — nobody asked for it by name.
     */
    @Transactional(readOnly = true)
    Applied resolve(UUID sellerId, UUID buyerId, String code, int subtotalCents,
                    int shippingCents) {
        OffsetDateTime now = OffsetDateTime.now();
        List<ProductPromotion> live = promotions.findBySellerIdAndActiveTrue(sellerId).stream()
            .filter(p -> p.liveAt(now))
            .toList();
        if (code != null && !code.isBlank()) {
            String wanted = code.trim().toUpperCase();
            ProductPromotion match = live.stream()
                .filter(p -> p.getCode().equals(wanted))
                .findFirst()
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "That code doesn't apply here"));
            int discount = usable(match, buyerId)
                ? guarded(match, subtotalCents, shippingCents) : 0;
            if (discount <= 0) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "That code doesn't apply to this basket");
            }
            return new Applied(match, discount);
        }
        return live.stream()
            .filter(p -> p.getCode().isEmpty() && usable(p, buyerId))
            .map(p -> new Applied(p, guarded(p, subtotalCents, shippingCents)))
            .filter(a -> a.discountCents() > 0)
            .max(Comparator.comparingInt(Applied::discountCents))
            .orElse(null);
    }

    @Transactional
    void recordRedemption(ProductPromotion promotion, UUID buyerId, UUID orderId) {
        redemptions.save(new ProductPromotionRedemption(promotion.getId(), buyerId, orderId));
    }

    /** A FREE_SHIPPING promotion on a basket that already ships free is a
     *  no-op today and money off goods the day shipping config changes — the
     *  same trap delivery M4 closed by name, closed the same way. */
    private static int guarded(ProductPromotion promotion, int subtotalCents, int shippingCents) {
        if (promotion.getKind() == ProductPromotion.Kind.FREE_SHIPPING && shippingCents <= 0) {
            return 0;
        }
        return promotion.discountFor(subtotalCents, shippingCents);
    }

    private boolean usable(ProductPromotion promotion, UUID buyerId) {
        return promotion.getPerUserLimit() <= 0
            || redemptions.countByPromotionIdAndUserId(promotion.getId(), buyerId)
                < promotion.getPerUserLimit();
    }

    // MARK: Seller console CRUD

    @Transactional
    ProductDtos.PromotionResponse create(Seller seller, ProductDtos.CreatePromotionRequest request) {
        ProductPromotion.Kind kind;
        try {
            kind = ProductPromotion.Kind.valueOf(request.kind().trim().toUpperCase());
        } catch (IllegalArgumentException unknown) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Unknown promotion kind " + request.kind());
        }
        ProductPromotion saved = promotions.save(new ProductPromotion(seller.getId(),
            request.code(), request.label(), kind, request.valueBps(), request.amountCents(),
            request.minBasketCents(), request.maxDiscountCents(), request.perUserLimit(),
            request.startsAt(), request.endsAt()));
        return toResponse(saved);
    }

    @Transactional
    void deactivate(Seller seller, UUID promotionId) {
        ProductPromotion promotion = promotions.findById(promotionId)
            .filter(p -> p.getSellerId().equals(seller.getId()))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such promotion"));
        promotion.deactivate();
        promotions.save(promotion);
    }

    @Transactional(readOnly = true)
    List<ProductDtos.PromotionResponse> mine(Seller seller) {
        return promotions.findBySellerIdOrderByCreatedAtDesc(seller.getId()).stream()
            .map(ProductPromotionService::toResponse)
            .toList();
    }

    private static ProductDtos.PromotionResponse toResponse(ProductPromotion p) {
        return new ProductDtos.PromotionResponse(p.getId(), p.getCode(), p.getLabel(),
            p.getKind().name(), p.getValueBps(), p.getAmountCents(), p.getMinBasketCents(),
            p.getMaxDiscountCents(), p.getPerUserLimit(), p.isActive(),
            p.getStartsAt(), p.getEndsAt());
    }
}
