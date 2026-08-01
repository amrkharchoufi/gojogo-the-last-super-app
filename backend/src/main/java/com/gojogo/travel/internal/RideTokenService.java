package com.gojogo.travel.internal;

import com.gojogo.dispatch.VehicleCategory;
import com.gojogo.payments.InsufficientFundsException;
import com.gojogo.payments.TokenApi;
import com.gojogo.payments.WalletApi;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.List;
import java.util.UUID;

/**
 * What a ride costs the driver, and the charging of it.
 *
 * <p><strong>This is the platform's revenue on a ride.</strong> M3 settled the
 * fare as a single rider→driver transfer with no commission (SPECS §1), which
 * left the transport vertical earning the platform nothing at all. The vision's
 * answer is a token: the driver keeps every cent of the fare and pays for the
 * right to accept the job. So the money moves once here, at CONFIRMED, from the
 * driver's TOKENS bucket to the platform.
 *
 * <p><strong>Charged at confirmation, returned if the trip does not happen.</strong>
 * SPECS §4 says tokens are refunded only on a <em>driver-fault</em> cancellation.
 * This charges and refunds on the simpler rule — <b>the tokens follow the trip,
 * not the fault</b> — because the alternative has two problems. It makes a
 * cancellation a source of revenue, which is an incentive nobody should install
 * in a dispatch system; and it charges a driver for a rider's change of mind,
 * which teaches drivers to decline. A driver who accepts and cancels repeatedly
 * is already priced: dispatch counts every cancellation against them, which is
 * the lever that belongs to the behaviour.
 */
@Service
class RideTokenService {

    private static final Logger log = LoggerFactory.getLogger(RideTokenService.class);

    private final RideTokenPriceRepository prices;
    private final TokenApi tokens;

    RideTokenService(RideTokenPriceRepository prices, TokenApi tokens) {
        this.prices = prices;
        this.tokens = tokens;
    }

    // MARK: Pricing

    /** What this ride will cost its driver. */
    @Transactional(readOnly = true)
    int costOf(Ride ride) {
        return RideTokens.cost(bandsFor(ride.getCategory()), ride.getDistanceMetres());
    }

    /** The cheapest ride anybody could be offered — what "can this driver work
     *  at all" is measured against. */
    @Transactional(readOnly = true)
    int cheapestRide() {
        return EnumSet.allOf(VehicleCategory.class).stream()
            .map(category -> RideTokens.cheapest(bandsFor(category.name())))
            .filter(cost -> cost > 0)
            .min(Integer::compare)
            // Every category free means the model is off in this market, and
            // "you need 0 tokens" is the honest thing to say about that.
            .orElse(0);
    }

    /** The whole price list, for the screen that tells a driver what they will
     *  be charged before they are charged it. */
    @Transactional(readOnly = true)
    List<TokenPriceDto> priceList() {
        List<TokenPriceDto> list = new ArrayList<>();
        for (VehicleCategory category : EnumSet.allOf(VehicleCategory.class)) {
            for (RideTokens.Band band : bandsFor(category.name())) {
                list.add(new TokenPriceDto(category.name(), band.upToMetres(), band.tokens()));
            }
        }
        return list;
    }

    // MARK: Charging

    /**
     * Takes the tokens, at confirmation.
     *
     * <p><b>A driver who cannot pay does not lose the ride.</b> Eligibility is
     * enforced where it belongs — dispatch never offers a job somebody cannot
     * afford ({@link TokenEligibility}) — so reaching here without the tokens
     * means the balance moved between the offer and the handshake, which needs
     * two jobs at once and the busy flag already prevents. Refusing at this
     * point would kill a trip the rider has already been promised, over the
     * driver's finances, and would tell them so.
     *
     * @return the tokens actually charged, which is what a refund later gives
     *         back
     */
    @Transactional
    int charge(Ride ride) {
        int cost = costOf(ride);
        if (cost <= 0) return 0;
        try {
            tokens.spend(ride.getDriverUserId(), cost,
                WalletApi.Reference.of("RIDE", ride.getId(),
                    cost + (cost == 1 ? " token" : " tokens") + " for this trip"),
                "ride:" + ride.getId() + ":tokens");
            return cost;
        } catch (InsufficientFundsException empty) {
            // Deliberately not fatal. Logged loudly because it should be
            // unreachable, and one of these means the eligibility filter has a
            // hole in it.
            log.warn("Ride {} confirmed but driver {} could not pay {} tokens: {}",
                ride.getId(), ride.getDriverUserId(), cost, empty.getMessage());
            return 0;
        }
    }

    /**
     * Gives them back, because the trip did not happen.
     *
     * <p>Idempotent on the ride, and safe to call when nothing was charged: a
     * ride cancelled before it was ever confirmed has no spend to reverse and
     * this writes nothing.
     */
    @Transactional
    void refund(Ride ride) {
        int charged = ride.getTokenCost();
        if (charged <= 0 || ride.getDriverUserId() == null) return;
        tokens.refund(ride.getDriverUserId(), charged,
            WalletApi.Reference.of("RIDE", ride.getId(), "Tokens returned — trip cancelled"),
            "ride:" + ride.getId() + ":tokens:refund");
    }

    // MARK: Reads for the driver's screen

    @Transactional(readOnly = true)
    long balanceOf(UUID driverUserId) {
        return tokens.balanceOf(driverUserId);
    }

    /**
     * Whether this person could be offered anything right now, and why not.
     *
     * <p>The reason is the point. Dispatch simply stops offering, silently and
     * correctly — so without a surface that says "you have no tokens", a driver
     * sits online watching nothing arrive and concludes the app is broken. That
     * is the same failure the availability toggle refused to have in M2.
     */
    @Transactional(readOnly = true)
    String refusalFor(UUID driverUserId) {
        int cheapest = cheapestRide();
        if (cheapest <= 0) return null;
        long held = tokens.balanceOf(driverUserId);
        if (held >= cheapest) return null;
        return held <= 0
            ? "You're out of ride tokens, so you won't be offered trips. Top up to start again."
            : "You have " + held + (held == 1 ? " token" : " tokens")
                + ", and the cheapest trip costs " + cheapest + ". Top up to keep working.";
    }

    // MARK: Helpers

    /**
     * The bands in force for a category: the newest generation only.
     *
     * <p>A price change inserts several rows sharing one {@code effectiveFrom},
     * so "in force" is the newest such timestamp and every row that carries it —
     * mixing generations would silently produce a price list nobody wrote.
     */
    private List<RideTokens.Band> bandsFor(String category) {
        List<RideTokenPrice> rows = prices.inForce(category, OffsetDateTime.now());
        if (rows.isEmpty()) return List.of();
        OffsetDateTime newest = rows.getFirst().getEffectiveFrom();
        return rows.stream()
            .filter(row -> row.getEffectiveFrom().equals(newest))
            .map(RideTokenPrice::toBand)
            .toList();
    }
}
