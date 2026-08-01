package com.gojogo.travel.internal;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Everything {@code travel} does in response to a dispatch event has to start
 * its <em>own</em> transaction.
 *
 * <p>This pins a defect that reached production in M3 and sat there until the
 * first real ride was accepted at the asking price (2026-08-01). An
 * {@code AFTER_COMMIT} listener runs with the just-committed transaction's
 * resources still bound to the thread, so a {@code @Transactional} method called
 * from one <em>joins</em> a transaction that is already finished, and its first
 * write fails with "no transaction is in progress". By then the dispatch job is
 * assigned — which leaves a driver marked busy for a ride that never confirmed
 * and a rider who is told nothing at all.
 *
 * <p>Asserted structurally rather than behaviourally, deliberately. Reproducing
 * it needs a real transaction manager, a real commit and a real event publisher,
 * none of which exist on this machine — which is precisely why it shipped. What
 * can be checked here is the rule: reachable from a listener, and it writes,
 * therefore {@code REQUIRES_NEW}.
 *
 * <p>The two names below are maintained by hand. A third entry point in
 * {@link DispatchOutcomeListener} means a third line here — there is no way to
 * read a method body by reflection, and a test that pretended to derive them
 * would only be comparing a list to itself.
 */
class ListenerTransactionTests {

    private static final List<String> CALLED_FROM_A_LISTENER =
        List.of("confirmFromDispatch", "exhaust");

    @Test
    @DisplayName("every dispatch-event handler starts its own transaction")
    void listenerEntryPointsRequireNew() {
        for (String name : CALLED_FROM_A_LISTENER) {
            Transactional annotation = methodNamed(name).getAnnotation(Transactional.class);
            assertThat(annotation)
                .as("%s is called from an AFTER_COMMIT listener and writes", name)
                .isNotNull();
            assertThat(annotation.propagation())
                .as("%s must not join a transaction that has already committed", name)
                .isEqualTo(Propagation.REQUIRES_NEW);
        }
    }

    @Test
    @DisplayName("the listener is still AFTER_COMMIT — which is why the rule exists")
    void theListenerStillRunsAfterCommit() {
        // Moving to BEFORE_COMMIT would make the propagation above unnecessary
        // and wrong — and would let a ride be confirmed off an assignment whose
        // transaction then rolls back, which is the failure AFTER_COMMIT is here
        // to prevent. If this ever changes, the rule above has to be rethought
        // rather than quietly kept.
        assertThat(Arrays.stream(DispatchOutcomeListener.class.getDeclaredMethods())
            .filter(m -> m.isAnnotationPresent(TransactionalEventListener.class))
            .map(m -> m.getAnnotation(TransactionalEventListener.class).phase()))
            .isNotEmpty()
            .allMatch(phase -> phase == TransactionPhase.AFTER_COMMIT);
    }

    private static Method methodNamed(String name) {
        return Arrays.stream(RideService.class.getDeclaredMethods())
            .filter(m -> m.getName().equals(name))
            .findFirst()
            .orElseThrow(() -> new AssertionError(
                "RideService." + name + " is gone — this test needs updating"));
    }
}
