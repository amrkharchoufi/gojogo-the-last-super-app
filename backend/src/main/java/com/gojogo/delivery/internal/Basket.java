package com.gojogo.delivery.internal;

/**
 * A priced basket: the one place delivery does money arithmetic.
 *
 * <p>Quoting and placing both go through here, so what a customer approved and
 * what they are charged cannot drift apart — two code paths computing the same
 * total is how people get billed for surprises. And because settlement reads the
 * same numbers back off the order, the splits are guaranteed to sum to what was
 * held.
 *
 * <p>The discount always comes off the merchant's side, free delivery included:
 * a merchant funds their own campaign, and no promotion may reduce what the
 * courier or the platform is paid.
 */
record Basket(int subtotalCents, int deliveryFeeCents, int serviceFeeCents,
              int discountCents, int tipCents, String currency) {

    static Basket of(int subtotalCents, int deliveryFeeCents, int serviceFeeCents,
                     int discountCents, int tipCents, String currency) {
        return new Basket(subtotalCents, deliveryFeeCents, serviceFeeCents,
            // A discount can never exceed the food it discounts.
            Math.clamp(discountCents, 0, subtotalCents),
            Math.max(0, tipCents), currency);
    }

    int totalCents() {
        return subtotalCents - discountCents + deliveryFeeCents + serviceFeeCents + tipCents;
    }

    /** What the merchant's share is calculated from, before commission. */
    int merchantBaseCents() {
        return subtotalCents - discountCents;
    }
}
