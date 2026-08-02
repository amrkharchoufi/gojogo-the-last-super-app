package com.gojogo.delivery.internal;

import java.security.SecureRandom;

/**
 * The pickup code and the delivery PIN: six digits, from a real random source.
 *
 * <p><b>{@link SecureRandom} rather than {@code Math.random()}</b>, and the
 * reason is not ceremony. These two numbers are the only thing standing between
 * "a courier collected this order" and "somebody said they did" — the delivery
 * PIN in particular is what a payment is made against. A predictable sequence is
 * a PIN somebody can compute from the last order they placed, which is exactly
 * the attack the code exists to stop, and there is no performance argument on
 * the other side: this runs twice per order, once.
 *
 * <p><b>Numeric, and zero-padded.</b> A pickup code is read aloud across a
 * counter by somebody who may not share a first language with the person typing
 * it, and letters make that harder in every direction — case, homoglyphs, and
 * alphabets that do not agree on what "B" sounds like. Digits also mean the
 * courier's keyboard is a number pad, which is the difference between a
 * one-handed tap and a fumble with food in the other hand. The padding matters
 * as much as the digits: {@code 000482} must not be shown as {@code 482}, or the
 * screen and the field disagree about a code that is in fact correct.
 */
final class HandoffCodes {

    private static final SecureRandom RANDOM = new SecureRandom();

    /** Six is the configured default. The bound is what the column can hold —
     *  a config row asking for twenty digits gets eight, rather than an insert
     *  that fails at the wrong end of an accept. */
    private static final int MIN_LENGTH = 4;
    private static final int MAX_LENGTH = 8;

    private HandoffCodes() {
    }

    static String numeric(int length) {
        int digits = Math.clamp(length, MIN_LENGTH, MAX_LENGTH);
        StringBuilder code = new StringBuilder(digits);
        for (int i = 0; i < digits; i++) {
            code.append(RANDOM.nextInt(10));
        }
        return code.toString();
    }

    /**
     * What a person actually typed, reduced to the digits in it.
     *
     * <p>A courier reading {@code 482 913} off a screen types the space, and a
     * client that helpfully formats the field sends it. Refusing a correct code
     * over whitespace is the kind of failure that gets blamed on the code rather
     * than on us, so the comparison happens on digits alone — which is safe
     * precisely because these codes are numeric and nothing else.
     */
    static String digitsOf(String typed) {
        if (typed == null) return "";
        StringBuilder digits = new StringBuilder(typed.length());
        for (int i = 0; i < typed.length(); i++) {
            char c = typed.charAt(i);
            if (c >= '0' && c <= '9') digits.append(c);
        }
        return digits.toString();
    }
}
