package com.gojogo.delivery.internal;

import java.util.List;
import java.util.UUID;

/**
 * A priced order: the one place delivery does money arithmetic.
 *
 * <p>Quoting and placing both go through here, so what a customer approved and
 * what they are charged cannot drift apart — two code paths computing the same
 * total is how people get billed for surprises. And because settlement reads the
 * same numbers back off the order and its sub-orders, the splits are guaranteed
 * to sum to what was held.
 *
 * <p>Since Phase 4 M3 an order can span merchants, so the shape is a slice per
 * merchant plus the two amounts that belong to the order as a whole: the service
 * fee (the platform charges per checkout, not per kitchen) and the tip (one
 * courier carries every bag). The top-level numbers are sums over the slices —
 * derived here, in one place, rather than wherever a caller happens to add.
 *
 * <p>The discount always comes off its own merchant's side, free delivery
 * included: a merchant funds their own campaign, and no promotion may reduce
 * what the courier or the platform is paid — or what another merchant is.
 */
record Basket(List<MerchantSlice> slices, int serviceFeeCents, int tipCents, String currency) {

    /** One merchant's part of the order, priced. */
    record MerchantSlice(UUID merchantId, int subtotalCents, int deliveryFeeCents,
                         int discountCents, UUID promotionId, String promotionCode,
                         String promotionLabel) {

        static MerchantSlice of(UUID merchantId, int subtotalCents, int deliveryFeeCents,
                                int discountCents, UUID promotionId, String promotionCode,
                                String promotionLabel) {
            return new MerchantSlice(merchantId, subtotalCents, deliveryFeeCents,
                // A discount can never exceed the food it discounts.
                Math.clamp(discountCents, 0, subtotalCents),
                promotionId,
                promotionCode == null ? "" : promotionCode,
                promotionLabel == null ? "" : promotionLabel);
        }

        /** What this merchant's share is calculated from, before commission. */
        int merchantBaseCents() {
            return subtotalCents - discountCents;
        }

        /** What cancelling this slice gives back: the food and this merchant's
         *  delivery fee. */
        int shareCents() {
            return merchantBaseCents() + deliveryFeeCents;
        }
    }

    static Basket of(List<MerchantSlice> slices, int serviceFeeCents, int tipCents,
                     String currency) {
        return new Basket(List.copyOf(slices), serviceFeeCents, Math.max(0, tipCents), currency);
    }

    /** The single-merchant shape, kept because most orders are one restaurant
     *  and every pre-M3 caller thinks in it. */
    static Basket of(UUID merchantId, int subtotalCents, int deliveryFeeCents,
                     int serviceFeeCents, int discountCents, int tipCents, String currency) {
        return of(List.of(MerchantSlice.of(merchantId, subtotalCents, deliveryFeeCents,
                discountCents, null, "", "")),
            serviceFeeCents, tipCents, currency);
    }

    int subtotalCents() {
        return slices.stream().mapToInt(MerchantSlice::subtotalCents).sum();
    }

    int deliveryFeeCents() {
        return slices.stream().mapToInt(MerchantSlice::deliveryFeeCents).sum();
    }

    int discountCents() {
        return slices.stream().mapToInt(MerchantSlice::discountCents).sum();
    }

    int totalCents() {
        return subtotalCents() - discountCents() + deliveryFeeCents()
            + serviceFeeCents + tipCents;
    }
}
