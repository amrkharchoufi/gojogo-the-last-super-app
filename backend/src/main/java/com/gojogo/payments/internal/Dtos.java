package com.gojogo.payments.internal;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/**
 * The wire shapes. Amounts are minor units everywhere, named {@code …Minor} so
 * nobody has to wonder — a field called {@code amount} carrying 1250 is how a
 * client eventually shows someone a bill for $1,250.
 */
final class Dtos {

    private Dtos() {
    }

    /**
     * @param topUpEnabled whether a card top-up can actually be started right
     *                     now — false on an environment with no Stripe keys or
     *                     no webhook secret, which the app reads to hide the
     *                     button rather than offer one that 503s
     */
    record WalletDto(String currency, long availableMinor, long escrowMinor, long stakingMinor,
                     long tokensMinor, long rewardsMinor, boolean topUpEnabled,
                     String publishableKey, long topUpMinMinor, long topUpMaxMinor,
                     /* What the TOKENS bucket divides by, so the wallet screen can say
                      * "12 tokens" without a second call or a constant of its own. */
                     long minorPerToken) {
    }

    /** Signed from the reader's point of view: negative means money left. */
    record TransactionDto(UUID id, long amountMinor, String currency, String kind,
                          String refKind, UUID refId, String memo, OffsetDateTime createdAt) {
    }

    record TopUpRequest(@Positive(message = "Choose an amount") long amountMinor) {
    }

    /** {@code checkoutUrl} is Stripe-hosted: the card never touches this
     *  backend or the app. */
    record TopUpResponse(UUID id, String checkoutUrl, long amountMinor, String currency) {
    }

    record TopUpDto(UUID id, long amountMinor, String currency, String status,
                    String checkoutUrl, OffsetDateTime createdAt) {
    }

    /**
     * The token shelf and what the caller has on it (Phase 3 M4).
     *
     * @param tokens        whole tokens — the number a driver acts on
     * @param tokensMinor   the same balance as the ledger holds it, so a client
     *                      that wants to show it as money doesn't have to
     *                      multiply and get it wrong
     * @param availableMinor spendable wallet, because a pack is bought out of it
     *                      and the app needs to know before it offers to
     * @param lowThreshold  the count below which a warning is sent, so the app
     *                      draws the same line the server does
     */
    record TokenWalletDto(long tokens, long tokensMinor, long minorPerToken,
                          long availableMinor, String currency, long lowThreshold,
                          List<TokenPackDto> packs, List<TransactionDto> movements) {
    }

    /** @param bonusTokens how many of {@code tokens} the platform is paying for */
    record TokenPackDto(UUID id, String name, int tokens, long priceMinor,
                        long bonusTokens, String note) {
    }

    record TokenPurchaseRequest(@NotNull UUID packId) {
    }

    record ConnectStatusDto(boolean exists, boolean detailsSubmitted, boolean payoutsEnabled,
                            String requirementsNote, boolean ready) {
    }

    record ConnectLinkResponse(String url) {
    }

    record PayoutRequest(@Positive(message = "Choose an amount") long amountMinor) {
    }

    record PayoutDto(UUID id, long amountMinor, String currency, String status,
                     String failureReason) {
    }
}
