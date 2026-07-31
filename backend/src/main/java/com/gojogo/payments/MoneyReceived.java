package com.gojogo.payments;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * A person's spendable balance went up. Published for {@link OwnerKind#USER}
 * credits only — a merchant's earnings are announced by the vertical that owns
 * the merchant, because only it knows which human to tell.
 *
 * <p>Consumed by {@code notifications} (SPECS.md §12: "payment received"). Not
 * published for a hold or a release: money moving between a person's own pockets
 * is not news, and a push for it would train people to ignore the ones that are.
 */
public record MoneyReceived(UUID profileId, long amountMinor, String currency, LedgerKind kind,
                            String refKind, UUID refId, String memo, OffsetDateTime at) {
}
