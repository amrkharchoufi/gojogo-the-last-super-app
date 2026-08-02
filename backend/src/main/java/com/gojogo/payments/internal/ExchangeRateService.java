package com.gojogo.payments.internal;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.gojogo.config.ConfigApi;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.MathContext;
import java.math.RoundingMode;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.time.Instant;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;

/**
 * What one platform dollar is worth where the person reading the screen lives.
 *
 * <p><strong>This converts what is shown, never what is charged.</strong> The
 * ledger is single-currency by design (SPECS §15, "single {@code
 * PLATFORM_CURRENCY} until a second market exists"): every balance, hold,
 * capture and payout is in {@link com.gojogo.payments.WalletApi#currency()}, and
 * the double-entry invariant depends on that being true. A stake of 3000 minor
 * units is $30 whoever is looking at it.
 *
 * <p>What was wrong was not the ledger — it was showing "$30" to somebody who
 * has never held a dollar and has no idea whether that is a coffee or a week's
 * wages. So this module answers a presentation question: <em>roughly how much is
 * that in money you think in?</em> Everything built on it is marked approximate,
 * and anywhere money actually moves the app shows the exact charged amount
 * beside the estimate. A number somebody will be billed and a number to help
 * them understand it are different things, and conflating them is how a customer
 * ends up arguing with a card statement.
 *
 * <p>Turning this into real multi-currency charging is a different and much
 * larger job — a rate recorded on every entry, FX gain and loss as its own
 * account, Stripe settlement currencies, refunds at the original rate — and
 * doing half of it is how money goes missing.
 *
 * <h2>Where the numbers come from</h2>
 *
 * <p>Three layers, each overriding the one before:
 *
 * <ol>
 *   <li>the table compiled in below, so a fresh install shows something sane;</li>
 *   <li>the config registry — {@code payments.fx.rate.MAD} and friends, in
 *       ten-thousandths, so an operator fixes a drifted rate without a deploy,
 *       which is the entire point of that module;</li>
 *   <li>a provider, if and only if {@code payments.fx.url} names one. Off by
 *       default: an unconfigured install should not be quietly reaching out to
 *       somebody's free API on a timer.</li>
 * </ol>
 *
 * <p>Rates are served with the moment they were taken, and the app says
 * "approximately" rather than pretending precision it hasn't got.
 */
@Service
class ExchangeRateService {

    private static final Logger log = LoggerFactory.getLogger(ExchangeRateService.class);

    /** Config values are integers, so a rate is carried in ten-thousandths: MAD
     *  at 9.9532 to the dollar is 99532. Four decimal places is finer than any
     *  currency's smallest coin and coarse enough to type. */
    private static final BigDecimal SCALE = BigDecimal.valueOf(10_000);
    private static final String RATE_PREFIX = "payments.fx.rate.";
    private static final String URL_KEY = "payments.fx.url";

    /**
     * A starting point, not a commitment — mid-market rates against the dollar
     * rounded to something a person would recognise, current to within a few
     * percent as of mid-2026. They exist so a new install shows a plausible
     * number rather than nothing; an operator who cares about precision sets
     * {@code payments.fx.rate.*} or points {@code payments.fx.url} at a feed.
     *
     * <p>Chosen for coverage of the markets this platform plausibly opens in
     * next, plus the currencies most people's phones are set to. A currency
     * absent from here and from config simply isn't offered a conversion, which
     * is the honest failure: the reader sees the platform amount, which is the
     * one that is true.
     */
    private static final Map<String, BigDecimal> COMPILED_IN = Map.ofEntries(
        Map.entry("MAD", new BigDecimal("9.9500")),   // Morocco
        Map.entry("DZD", new BigDecimal("134.0000")), // Algeria
        Map.entry("TND", new BigDecimal("3.1000")),   // Tunisia
        Map.entry("EGP", new BigDecimal("48.5000")),  // Egypt
        Map.entry("XOF", new BigDecimal("600.0000")), // Senegal, Côte d'Ivoire, Mali…
        Map.entry("XAF", new BigDecimal("600.0000")), // Cameroon, Gabon, Congo…
        Map.entry("NGN", new BigDecimal("1550.0000")),// Nigeria
        Map.entry("GHS", new BigDecimal("15.5000")),  // Ghana
        Map.entry("KES", new BigDecimal("129.0000")), // Kenya
        Map.entry("ZAR", new BigDecimal("18.0000")),  // South Africa
        Map.entry("EUR", new BigDecimal("0.9200")),
        Map.entry("GBP", new BigDecimal("0.7800")),
        Map.entry("CHF", new BigDecimal("0.8800")),
        Map.entry("SEK", new BigDecimal("10.5000")),
        Map.entry("NOK", new BigDecimal("10.8000")),
        Map.entry("DKK", new BigDecimal("6.8500")),
        Map.entry("PLN", new BigDecimal("3.9500")),
        Map.entry("TRY", new BigDecimal("39.0000")),  // Türkiye
        Map.entry("AED", new BigDecimal("3.6725")),   // pegged
        Map.entry("SAR", new BigDecimal("3.7500")),   // pegged
        Map.entry("QAR", new BigDecimal("3.6400")),   // pegged
        Map.entry("INR", new BigDecimal("86.0000")),
        Map.entry("PKR", new BigDecimal("280.0000")),
        Map.entry("BDT", new BigDecimal("121.0000")),
        Map.entry("IDR", new BigDecimal("16300.0000")),
        Map.entry("PHP", new BigDecimal("58.0000")),
        Map.entry("VND", new BigDecimal("25400.0000")),
        Map.entry("THB", new BigDecimal("34.0000")),
        Map.entry("MYR", new BigDecimal("4.3000")),
        Map.entry("CNY", new BigDecimal("7.1500")),
        Map.entry("JPY", new BigDecimal("152.0000")), // no minor units at all
        Map.entry("KRW", new BigDecimal("1380.0000")),
        Map.entry("BRL", new BigDecimal("5.6000")),
        Map.entry("MXN", new BigDecimal("18.5000")),
        Map.entry("ARS", new BigDecimal("1050.0000")),
        Map.entry("COP", new BigDecimal("4200.0000")),
        Map.entry("CLP", new BigDecimal("960.0000")),
        Map.entry("CAD", new BigDecimal("1.3800")),
        Map.entry("AUD", new BigDecimal("1.5400")),
        Map.entry("NZD", new BigDecimal("1.6800")));

    private final ConfigApi config;
    private final LedgerService ledger;
    private final ObjectMapper json;
    private final HttpClient http = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(5)).build();

    /** The last good answer from a provider, if one is configured. Held in
     *  memory on purpose: a rate table is a cache, and losing it on restart
     *  costs one HTTP call and falls back to config in the meantime. */
    private final AtomicReference<Fetched> fetched = new AtomicReference<>();

    private record Fetched(Map<String, BigDecimal> rates, Instant at) {
    }

    ExchangeRateService(ConfigApi config, LedgerService ledger, ObjectMapper json) {
        this.config = config;
        this.ledger = ledger;
        this.json = json;
    }

    // MARK: What the app asks for

    /**
     * Every rate we can offer against the platform currency, plus when they were
     * taken and whether anything checked them today.
     *
     * <p>The base is never in the map. One dollar is one dollar; a client that
     * found {@code USD: 1} in here would be a client one refactor away from
     * "converting" the platform currency into itself and rounding it.
     */
    Dtos.RatesDto snapshot() {
        String base = ledger.currency();
        Fetched live = fetched.get();
        Map<String, String> rates = new LinkedHashMap<>();
        for (Map.Entry<String, BigDecimal> entry : effectiveRates(base, live).entrySet()) {
            rates.put(entry.getKey(), entry.getValue().toPlainString());
        }
        return new Dtos.RatesDto(base, rates,
            live == null ? null : live.at().toString(), live != null);
    }

    /**
     * The rate for one currency, for a caller that wants a single number rather
     * than the table. Empty when there isn't one — which is a real answer and
     * must not be papered over with 1.0.
     */
    Optional<BigDecimal> rate(String currency) {
        if (currency == null) return Optional.empty();
        String wanted = currency.trim().toUpperCase();
        if (wanted.equals(ledger.currency())) return Optional.of(BigDecimal.ONE);
        return Optional.ofNullable(effectiveRates(ledger.currency(), fetched.get()).get(wanted));
    }

    private Map<String, BigDecimal> effectiveRates(String base, Fetched live) {
        Map<String, BigDecimal> merged = new LinkedHashMap<>(COMPILED_IN);
        if (live != null) merged.putAll(live.rates());
        // Config last: an operator correcting a rate by hand is overriding both
        // the shipped guess and the feed, which is what "by hand" has to mean.
        for (String currency : merged.keySet().toArray(String[]::new)) {
            configRate(currency).ifPresent(rate -> merged.put(currency, rate));
        }
        merged.remove(base);
        merged.entrySet().removeIf(entry -> entry.getValue().signum() <= 0);
        return merged;
    }

    private Optional<BigDecimal> configRate(String currency) {
        long tenThousandths = config.number(RATE_PREFIX + currency, 0);
        return tenThousandths <= 0 ? Optional.empty()
            : Optional.of(BigDecimal.valueOf(tenThousandths)
                .divide(SCALE, 6, RoundingMode.HALF_UP));
    }

    // MARK: Keeping them current

    /**
     * Pulls a fresh table, if a provider is configured. Silent no-op otherwise.
     *
     * <p>Failure is deliberately quiet and total: the previous table stays, the
     * app keeps showing an older `asOf`, and nothing on a money screen changes
     * because a third party had a bad afternoon. A stale approximation clearly
     * labelled as one is a far better outcome than an error where a price
     * should be.
     */
    void refresh() {
        String url = config.string(URL_KEY, "").trim();
        if (url.isBlank()) return;
        try {
            HttpResponse<String> response = http.send(
                HttpRequest.newBuilder(URI.create(url))
                    .timeout(Duration.ofSeconds(10))
                    .header("Accept", "application/json")
                    .GET().build(),
                HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() / 100 != 2) {
                log.warn("FX provider answered {} — keeping the rates we have",
                    response.statusCode());
                return;
            }
            Map<String, BigDecimal> parsed = parse(json.readTree(response.body()),
                ledger.currency());
            if (parsed.isEmpty()) {
                log.warn("FX provider returned nothing usable — keeping the rates we have");
                return;
            }
            fetched.set(new Fetched(parsed, Instant.now()));
            log.info("FX rates refreshed: {} currencies against {}", parsed.size(),
                ledger.currency());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } catch (Exception e) {
            log.warn("FX refresh failed ({}) — keeping the rates we have", e.toString());
        }
    }

    /**
     * Reads the shape every free rates feed happens to share: a {@code rates}
     * object of currency to number, and a {@code base} naming what they are
     * against.
     *
     * <p>Two things it refuses rather than guesses. A feed quoting a base that
     * isn't ours is dropped whole — silently treating EUR-based rates as
     * dollar-based would misprice every screen by a fifth, and there is no
     * outcome worse than *plausible* wrong money. And any entry that isn't a
     * positive number is skipped rather than defaulting, because a zero rate
     * would render every price as nothing at all.
     */
    static Map<String, BigDecimal> parse(JsonNode body, String expectedBase) {
        Map<String, BigDecimal> rates = new LinkedHashMap<>();
        if (body == null) return rates;
        JsonNode base = body.get("base");
        if (base != null && base.isTextual()
            && !base.asText().trim().equalsIgnoreCase(expectedBase)) {
            log.warn("FX provider quotes {} but the ledger is {} — ignoring the whole table",
                base.asText(), expectedBase);
            return rates;
        }
        JsonNode table = body.get("rates");
        if (table == null || !table.isObject()) return rates;
        for (Iterator<String> it = table.fieldNames(); it.hasNext(); ) {
            String currency = it.next();
            JsonNode value = table.get(currency);
            if (value == null || !value.isNumber()) continue;
            BigDecimal rate = value.decimalValue();
            if (rate.signum() <= 0) continue;
            rates.put(currency.trim().toUpperCase(),
                rate.round(new MathContext(10)).stripTrailingZeros());
        }
        return rates;
    }
}
