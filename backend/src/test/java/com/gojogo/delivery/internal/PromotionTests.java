package com.gojogo.delivery.internal;

import org.junit.jupiter.api.Test;

import java.time.OffsetDateTime;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * What a promotion is worth, and when it is worth nothing. Pure arithmetic over
 * the rules a merchant set — no database, no basket.
 */
class PromotionTests {

    private static Promotion percent(int bps, int minBasket, int cap) {
        return new Promotion(UUID.randomUUID(), "SAVE", "Save", Promotion.Kind.PERCENT,
            bps, 0, minBasket, cap, 0, null, null);
    }

    @Test
    void percentageIsBasisPointsOfTheFood() {
        assertThat(percent(1_000, 0, 0).discountFor(2_500, 300)).isEqualTo(250);
    }

    /** Rounded down, so a half-cent goes to the merchant rather than to the
     *  discount — one cent per order, and the wrong side of it is not worth
     *  explaining to anybody. */
    @Test
    void percentageRoundsDown() {
        assertThat(percent(1_000, 0, 0).discountFor(999, 0)).isEqualTo(99);
    }

    @Test
    void capBeatsPercentage() {
        assertThat(percent(5_000, 0, 400).discountFor(10_000, 0)).isEqualTo(400);
    }

    @Test
    void basketBelowTheMinimumGetsNothing() {
        assertThat(percent(1_000, 3_000, 0).discountFor(2_999, 0)).isZero();
    }

    @Test
    void freeDeliveryIsWorthWhateverDeliveryCostsToday() {
        Promotion promotion = new Promotion(UUID.randomUUID(), null, "Free delivery",
            Promotion.Kind.FREE_DELIVERY, 0, 0, 0, 0, 0, null, null);
        assertThat(promotion.discountFor(2_000, 349)).isEqualTo(349);
    }

    /** Even a fixed promotion cannot take off more than the food is worth. */
    @Test
    void fixedIsCappedAtTheSubtotal() {
        Promotion promotion = new Promotion(UUID.randomUUID(), "TENOFF", "$10 off",
            Promotion.Kind.FIXED, 0, 1_000, 0, 0, 0, null, null);
        assertThat(promotion.discountFor(600, 300)).isEqualTo(600);
    }

    @Test
    void aWindowThatHasNotOpenedIsNotLive() {
        OffsetDateTime now = OffsetDateTime.now();
        Promotion future = new Promotion(UUID.randomUUID(), null, "Soon",
            Promotion.Kind.FIXED, 0, 500, 0, 0, 0, now.plusDays(1), null);
        Promotion past = new Promotion(UUID.randomUUID(), null, "Over",
            Promotion.Kind.FIXED, 0, 500, 0, 0, 0, null, now.minusMinutes(1));
        assertThat(future.liveAt(now)).isFalse();
        assertThat(past.liveAt(now)).isFalse();
        assertThat(new Promotion(UUID.randomUUID(), null, "Now", Promotion.Kind.FIXED,
            0, 500, 0, 0, 0, now.minusDays(1), now.plusDays(1)).liveAt(now)).isTrue();
    }
}
