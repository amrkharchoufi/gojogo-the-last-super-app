package com.gojogo.payments;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Money left the platform for a payee's bank. The person notified is whoever
 * asked for it ({@code requestedBy} on the payout), which for a merchant is its
 * owner and later, in GoJoAdmin, may be an operator acting for them.
 *
 * <p>Consumed by {@code notifications} (SPECS.md §12: "payout sent").
 */
public record PayoutSent(UUID profileId, UUID payoutId, long amountMinor, String currency,
                         OffsetDateTime at) {
}
