package com.gojogo.payments.internal;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Keeps the display rates roughly current.
 *
 * <p>Six-hourly, because these numbers decorate prices rather than settle them:
 * the ledger is single-currency and nothing here changes what anybody is
 * charged, so chasing the mid-market minute by minute would be a lot of traffic
 * in exchange for a digit nobody reads. A pegged currency — the dirham is
 * managed, the Gulf currencies are pegged outright — barely moves between one
 * tick and the next.
 *
 * <p>Does nothing at all unless {@code payments.fx.url} names a provider. An
 * install that hasn't asked for a feed keeps the shipped table and whatever an
 * operator has set by hand, and reaches out to nobody.
 */
@Component
class ExchangeRateJob {

    private final ExchangeRateService rates;

    ExchangeRateJob(ExchangeRateService rates) {
        this.rates = rates;
    }

    @Scheduled(fixedDelayString = "${gojogo.payments.fx-poll-ms:21600000}",
        initialDelayString = "${gojogo.payments.fx-initial-delay-ms:30000}")
    void tick() {
        rates.refresh();
    }
}
