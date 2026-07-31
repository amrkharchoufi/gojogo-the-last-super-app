package com.gojogo.payments.internal;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** What the platform takes. Rounding here is the difference between a merchant
 *  trusting their statement and querying it. */
class FeePolicyTests {

    @Test
    void percentageOfTheBase() {
        assertThat(new FeePolicy("DELIVERY", 1_500, 0).feeOn(2_000)).isEqualTo(300);
    }

    /** Down, always: a half-cent goes to the party that earned the money, never
     *  to the platform. */
    @Test
    void roundsDown() {
        assertThat(new FeePolicy("DELIVERY", 1_500, 0).feeOn(1_999)).isEqualTo(299);
    }

    @Test
    void fixedComponentIsAddedOnTop() {
        assertThat(new FeePolicy("ECONOMY", 1_000, 30).feeOn(1_000)).isEqualTo(130);
    }

    /** A fee larger than what is being settled would make the payee's share
     *  negative — the split would then not sum to the hold, and settlement would
     *  refuse. Capping here means that can't arise from policy alone. */
    @Test
    void neverExceedsTheBase() {
        assertThat(new FeePolicy("DELIVERY", 10_000, 500).feeOn(1_000)).isEqualTo(1_000);
    }

    @Test
    void nothingToTakeAcutOf() {
        assertThat(new FeePolicy("DELIVERY", 1_500, 50).feeOn(0)).isZero();
    }

    /** The travel row exists precisely so this is a decision on the record
     *  rather than a missing policy read as zero by accident. */
    @Test
    void zeroPolicyTakesNothing() {
        assertThat(new FeePolicy("TRAVEL", 0, 0).feeOn(50_000)).isZero();
    }
}
