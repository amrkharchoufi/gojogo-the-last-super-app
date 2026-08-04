package com.gojogo.delivery.internal;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Checkout arithmetic. Every case here is one where being wrong means either
 * charging someone the wrong amount or stranding money in escrow that no split
 * claims — the two failures nobody notices for a month. Since Phase 4 M3 the
 * basket is a slice per merchant plus the two order-level amounts, and the
 * top-level numbers are sums over the slices.
 */
class BasketTests {

    private static final UUID FORNO = UUID.randomUUID();
    private static final UUID SUSHI = UUID.randomUUID();

    @Test
    void totalIsFoodMinusDiscountPlusFeesPlusTip() {
        Basket basket = Basket.of(FORNO, 2_000, 300, 99, 500, 250, "USD");
        assertThat(basket.totalCents()).isEqualTo(2_000 - 500 + 300 + 99 + 250);
    }

    /**
     * The invariant settlement depends on: the splits are computed from these
     * same numbers, so if the total were anything other than the sum of its
     * parts, {@code OrderPayments.settle} would refuse to settle.
     */
    @Test
    void totalIsExactlyTheSumOfWhatEachPayeeGets() {
        Basket basket = Basket.of(FORNO, 2_000, 300, 99, 500, 250, "USD");
        int merchantSide = basket.slices().getFirst().merchantBaseCents();  // food − discount
        int courierSide = basket.deliveryFeeCents() + basket.tipCents();
        int platformSide = basket.serviceFeeCents();
        assertThat(merchantSide + courierSide + platformSide).isEqualTo(basket.totalCents());
    }

    /**
     * Two kitchens, one checkout: the totals are sums over the slices, each
     * slice's discount stays its own merchant's, the service fee is charged
     * once, and — the part a cancellation depends on — every slice's share plus
     * the two order-level amounts is exactly the total.
     */
    @Test
    void twoMerchantsSumWithOneServiceFee() {
        Basket basket = Basket.of(List.of(
                Basket.MerchantSlice.of(FORNO, 2_000, 300, 500, null, "WELCOME10", "Welcome"),
                Basket.MerchantSlice.of(SUSHI, 3_000, 400, 0, null, "", "")),
            99, 250, "USD");

        assertThat(basket.subtotalCents()).isEqualTo(5_000);
        assertThat(basket.deliveryFeeCents()).isEqualTo(700);
        assertThat(basket.discountCents()).isEqualTo(500);
        assertThat(basket.totalCents()).isEqualTo(5_000 - 500 + 700 + 99 + 250);
        int shares = basket.slices().stream().mapToInt(Basket.MerchantSlice::shareCents).sum();
        assertThat(shares + basket.serviceFeeCents() + basket.tipCents())
            .isEqualTo(basket.totalCents());
    }

    /** A discount larger than the food it discounts would push the merchant's
     *  own share negative — the platform funding someone else's campaign. */
    @Test
    void discountNeverExceedsTheFood() {
        Basket basket = Basket.of(FORNO, 1_000, 300, 99, 5_000, 0, "USD");
        assertThat(basket.discountCents()).isEqualTo(1_000);
        assertThat(basket.slices().getFirst().merchantBaseCents()).isZero();
        assertThat(basket.totalCents()).isEqualTo(300 + 99);
    }

    /** Free delivery is funded by the merchant like every other promotion, so
     *  the courier's fee is still in the total and still paid in full. */
    @Test
    void freeDeliveryStillPaysTheCourier() {
        Basket basket = Basket.of(FORNO, 2_000, 300, 99, 300, 0, "USD");
        assertThat(basket.deliveryFeeCents()).isEqualTo(300);
        assertThat(basket.slices().getFirst().merchantBaseCents()).isEqualTo(1_700);
        assertThat(basket.totalCents()).isEqualTo(2_000 - 300 + 300 + 99);
    }

    @Test
    void negativeTipIsNotATip() {
        assertThat(Basket.of(FORNO, 1_000, 0, 0, 0, -500, "USD").tipCents()).isZero();
    }
}
