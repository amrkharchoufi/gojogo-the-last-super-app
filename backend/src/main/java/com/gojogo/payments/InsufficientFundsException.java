package com.gojogo.payments;

/**
 * Not enough in the bucket. A checked-in-spirit outcome rather than a failure:
 * the caller is expected to catch it and tell the customer to top up, which is
 * why it carries the numbers needed to say by how much.
 *
 * <p>A plain runtime exception rather than a {@code ResponseStatusException} so
 * that a vertical decides how it reads to <em>its</em> user — delivery turns it
 * into a 402 with a wallet-shaped message, and a background settlement job turns
 * it into a retry.
 */
public class InsufficientFundsException extends RuntimeException {

    private final long requiredMinor;
    private final long availableMinor;
    private final String currency;

    public InsufficientFundsException(long requiredMinor, long availableMinor, String currency) {
        super("Needs %d but only %d is available (%s)"
            .formatted(requiredMinor, availableMinor, currency));
        this.requiredMinor = requiredMinor;
        this.availableMinor = availableMinor;
        this.currency = currency;
    }

    public long requiredMinor() {
        return requiredMinor;
    }

    public long availableMinor() {
        return availableMinor;
    }

    /** What the caller has to add. Never negative. */
    public long shortfallMinor() {
        return Math.max(0, requiredMinor - availableMinor);
    }

    public String currency() {
        return currency;
    }
}
