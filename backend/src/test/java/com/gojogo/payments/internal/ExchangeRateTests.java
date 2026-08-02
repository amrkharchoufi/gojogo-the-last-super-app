package com.gojogo.payments.internal;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.gojogo.config.ConfigApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * The rates behind "≈ 298,50 MAD".
 *
 * <p>None of this settles anything — the ledger is single-currency and these
 * numbers decorate a price rather than charge it. Which is exactly why the tests
 * that matter are the ones about *refusing*: a wrong rate here doesn't bounce
 * off a balance check or fail reconciliation, it just quietly shows somebody a
 * number that is off by a fifth and looks entirely plausible.
 */
class ExchangeRateTests {

    private static final ObjectMapper JSON = new ObjectMapper();

    private ConfigApi config;
    private LedgerService ledger;
    private ExchangeRateService rates;

    @BeforeEach
    void setUp() {
        config = mock(ConfigApi.class);
        ledger = mock(LedgerService.class);
        when(ledger.currency()).thenReturn("USD");
        when(config.number(anyString(), anyLong()))
            .thenAnswer(call -> call.getArgument(1, Long.class));
        when(config.string(anyString(), anyString()))
            .thenAnswer(call -> call.getArgument(1, String.class));
        rates = new ExchangeRateService(config, ledger, JSON);
    }

    // MARK: What a feed is allowed to say

    @Test
    @DisplayName("a feed quoting a different base is dropped whole — euro rates "
        + "read as dollars would misprice every screen by a fifth")
    void aForeignBaseIsRefusedEntirely() throws Exception {
        var body = JSON.readTree("""
            {"base":"EUR","rates":{"MAD":10.8,"GBP":0.85}}""");

        assertThat(ExchangeRateService.parse(body, "USD")).isEmpty();
    }

    @Test
    @DisplayName("a feed with no base at all is trusted — most of them omit it "
        + "when you asked for one currency")
    void anAbsentBaseIsAssumedToBeOurs() throws Exception {
        var body = JSON.readTree("""
            {"rates":{"MAD":9.87}}""");

        assertThat(ExchangeRateService.parse(body, "USD"))
            .containsEntry("MAD", new BigDecimal("9.87"));
    }

    @Test
    @DisplayName("zero, negative and non-numeric rates are skipped, not defaulted "
        + "— a zero rate renders every price as nothing at all")
    void unusableEntriesAreSkipped() throws Exception {
        var body = JSON.readTree("""
            {"rates":{"MAD":9.95,"AAA":0,"BBB":-3,"CCC":"nine","DDD":null}}""");

        assertThat(ExchangeRateService.parse(body, "USD")).containsOnlyKeys("MAD");
    }

    @Test
    @DisplayName("a response with no rates object leaves the table alone rather "
        + "than emptying it")
    void junkLeavesNothingBehind() throws Exception {
        assertThat(ExchangeRateService.parse(JSON.readTree("{\"error\":\"nope\"}"), "USD"))
            .isEmpty();
        assertThat(ExchangeRateService.parse(null, "USD")).isEmpty();
    }

    // MARK: What the app is served

    @Test
    @DisplayName("the platform's own currency is never a rate — one dollar is one "
        + "dollar, and a client that found USD:1 here would convert it")
    void theBaseIsNotInTheTable() {
        Map<String, String> table = rates.snapshot().rates();

        assertThat(table).doesNotContainKey("USD");
        assertThat(rates.snapshot().base()).isEqualTo("USD");
    }

    @Test
    @DisplayName("a currency nobody has a rate for gets no conversion, rather "
        + "than 1:1 — the honest failure is showing the amount that is true")
    void anUnknownCurrencyConvertsToNothing() {
        assertThat(rates.rate("ZZZ")).isEmpty();
        assertThat(rates.rate(null)).isEmpty();
    }

    @Test
    @DisplayName("an operator's hand-set rate wins over the shipped one, without "
        + "a deploy — which is what the config module is for")
    void configOverridesTheCompiledInTable() {
        when(config.number("payments.fx.rate.MAD", 0)).thenReturn(101_500L);

        assertThat(rates.rate("MAD")).hasValueSatisfying(rate ->
            assertThat(rate).isEqualByComparingTo(new BigDecimal("10.15")));
    }

    @Test
    @DisplayName("asking for the platform currency answers 1 — it is the one "
        + "conversion that is exactly right")
    void theBaseConvertsToItself() {
        assertThat(rates.rate("usd")).hasValueSatisfying(rate ->
            assertThat(rate).isEqualByComparingTo(BigDecimal.ONE));
    }

    @Test
    @DisplayName("with no provider configured nothing is fetched and nothing is "
        + "lost — an install that didn't ask for a feed calls nobody")
    void noProviderMeansNoTraffic() {
        rates.refresh();

        assertThat(rates.snapshot().live()).isFalse();
        assertThat(rates.snapshot().asOf()).isNull();
        // The shipped table is still there, so screens still convert.
        assertThat(rates.snapshot().rates()).containsKey("MAD");
    }
}
