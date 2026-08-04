package com.gojogo.delivery.internal;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * Free delivery on an order nobody delivers (SPECS §5, Phase 4 M4).
 *
 * <p>The rule is cheap now and expensive later, which is why it is written down
 * rather than left to arithmetic: {@code discountFor} would return zero on a
 * pickup anyway, because the fee it is a percentage of is zero. That is an
 * accident of the numbers, not a decision, and the day somebody makes free
 * delivery worth a flat amount it would silently become money off food — which
 * is precisely what §6's "a discount is an honest order line" exists to stop.
 */
class PickupPromotionTests {

    private static final UUID MERCHANT = UUID.randomUUID();
    private static final UUID ME = UUID.randomUUID();

    private PromotionRepository promotions;
    private PromotionService service;

    @BeforeEach
    void setUp() {
        promotions = mock(PromotionRepository.class);
        PromotionRedemptionRepository redemptions = mock(PromotionRedemptionRepository.class);
        service = new PromotionService(promotions, redemptions);
    }

    @Test
    @DisplayName("a free-delivery code on a collection is refused by name")
    void freeDeliveryIsRefusedOnAPickup() {
        Promotion freeDelivery = promotion(Promotion.Kind.FREE_DELIVERY, "FREESHIP");
        when(promotions.findByMerchantIdAndCodeIgnoreCase(MERCHANT, "FREESHIP"))
            .thenReturn(Optional.of(freeDelivery));

        assertThatThrownBy(() -> service.resolve(MERCHANT, ME, "FREESHIP", 2_000, 0, true))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("for delivery orders")
            .extracting(e -> ((ResponseStatusException) e).getStatusCode())
            .isEqualTo(HttpStatus.CONFLICT);
    }

    @Test
    void theSameCodeStillWorksOnADelivery() {
        Promotion freeDelivery = promotion(Promotion.Kind.FREE_DELIVERY, "FREESHIP");
        when(promotions.findByMerchantIdAndCodeIgnoreCase(MERCHANT, "FREESHIP"))
            .thenReturn(Optional.of(freeDelivery));

        PromotionService.Applied applied =
            service.resolve(MERCHANT, ME, "FREESHIP", 2_000, 349, false);

        assertThat(applied.discountCents()).isEqualTo(349);
    }

    @Test
    @DisplayName("a percentage code is unaffected by which way the food travels")
    void aFoodDiscountAppliesEitherWay() {
        when(promotions.findByMerchantIdAndCodeIgnoreCase(MERCHANT, "SAVE10"))
            .thenReturn(Optional.of(promotion(Promotion.Kind.PERCENT, "SAVE10")));

        assertThat(service.resolve(MERCHANT, ME, "SAVE10", 2_000, 0, true).discountCents())
            .isEqualTo(200);
    }

    /** Nobody typed anything, so there is nobody to refuse: an automatic
     *  free-delivery promotion is skipped, and whatever else the kitchen runs
     *  still applies. */
    @Test
    void anAutomaticFreeDeliveryIsSkippedRatherThanRefused() {
        Promotion automaticFreeDelivery = promotion(Promotion.Kind.FREE_DELIVERY, null);
        Promotion automaticTenPercent = promotion(Promotion.Kind.PERCENT, null);
        when(promotions.findByMerchantIdAndActiveTrue(MERCHANT))
            .thenReturn(List.of(automaticFreeDelivery, automaticTenPercent));

        PromotionService.Applied applied = service.resolve(MERCHANT, ME, null, 2_000, 0, true);

        assertThat(applied.discountCents()).isEqualTo(200);
    }

    private static Promotion promotion(Promotion.Kind kind, String code) {
        return new Promotion(MERCHANT, code, "Promo", kind, 1_000, 500, 0, 0, 0, null, null);
    }
}
