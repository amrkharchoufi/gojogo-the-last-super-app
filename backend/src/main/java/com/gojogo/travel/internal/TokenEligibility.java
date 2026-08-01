package com.gojogo.travel.internal;

import com.gojogo.dispatch.JobKind;
import com.gojogo.dispatch.WorkerEligibility;
import com.gojogo.payments.TokenApi;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

/**
 * "Don't offer this trip to a driver who can't pay for it" — SPECS §4's rule
 * that a driver below the minimum balance "is filtered out by dispatch, not
 * blocked from the app".
 *
 * <p>The interface belongs to {@code dispatch} and the implementation belongs
 * here, which is the same direction {@code social} implements
 * {@code messaging.ConversationGuard} in. Dispatch must not learn what a token
 * is: its offer book asks "will you do this job" and has no opinion about money,
 * exactly as it has none about a fare. So this module — which knows what a ride
 * costs, because it prices one — answers the question, and dispatch only knows
 * that somebody objected.
 *
 * <p>The check is <b>per ride</b>, not per driver, because the cost is: a short
 * hop and a cross-city trip are different numbers of tokens, and a single "can
 * this person work" flag would have to assume the most expensive ride and lock
 * people out of trips they could comfortably afford.
 *
 * <p>Being filtered out is deliberately silent from dispatch's side. The driver
 * learns why from {@code GET /v1/travel/tokens}, which is this module's own
 * surface and the one place that can explain it.
 */
@Component
class TokenEligibility implements WorkerEligibility {

    private final RideRepository rides;
    private final RideTokenService tokenPrices;
    private final TokenApi tokens;

    TokenEligibility(RideRepository rides, RideTokenService tokenPrices, TokenApi tokens) {
        this.rides = rides;
        this.tokenPrices = tokenPrices;
        this.tokens = tokens;
    }

    @Override
    @Transactional(readOnly = true)
    public String refuseOffer(JobKind jobKind, UUID jobRefId, UUID workerUserId) {
        // Deliveries are not this module's business, and a courier does not
        // spend ride tokens. Phase 4 may or may not want its own rule; it will
        // add its own implementation rather than widening this one.
        if (jobKind != JobKind.RIDE) return null;
        Ride ride = rides.findById(jobRefId).orElse(null);
        // A job id this module has never heard of is not one it may veto. Saying
        // no to work we cannot price would turn a bug in another module into
        // drivers receiving nothing.
        if (ride == null) return null;
        int cost = tokenPrices.costOf(ride);
        if (cost <= 0) return null;
        long held = tokens.balanceOf(workerUserId);
        return held >= cost ? null
            : "needs " + cost + " tokens for this trip and holds " + held;
    }
}
