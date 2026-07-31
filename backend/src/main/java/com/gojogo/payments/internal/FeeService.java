package com.gojogo.payments.internal;

import com.gojogo.payments.FeeApi;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;

/** Reads {@code payments.fee_policy}: the newest row that had taken effect. */
@Service
class FeeService implements FeeApi {

    private final FeePolicyRepository policies;

    FeeService(FeePolicyRepository policies) {
        this.policies = policies;
    }

    @Override
    @Transactional(readOnly = true)
    public long platformFee(String vertical, long baseMinor) {
        return inForce(vertical).map(policy -> policy.feeOn(baseMinor)).orElse(0L);
    }

    @Override
    @Transactional(readOnly = true)
    public Policy policyFor(String vertical) {
        return inForce(vertical)
            .map(policy -> new Policy(vertical, policy.getPercentBps(), policy.getFixedMinor()))
            .orElseGet(() -> Policy.none(vertical));
    }

    private java.util.Optional<FeePolicy> inForce(String vertical) {
        List<FeePolicy> found = policies.inForce(vertical, OffsetDateTime.now(),
            PageRequest.of(0, 1));
        return found.isEmpty() ? java.util.Optional.empty() : java.util.Optional.of(found.get(0));
    }
}
