package com.gojogo.delivery.internal;

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
 * The delivery twin of {@code travel}'s {@code ListenerTransactionTests}, and it
 * exists because this milestone is the second module to hang work off a dispatch
 * event — which makes the defect that shipped in Phase 3 M3 a pattern rather
 * than an incident.
 *
 * <p>That one was live for a day: an {@code AFTER_COMMIT} listener runs with the
 * just-committed transaction's resources still bound to the thread, so a
 * {@code @Transactional} method called from one joins a transaction that is
 * already finished and the first write fails with "no transaction is in
 * progress". The dispatch job is assigned by then, so the visible damage is a
 * worker marked busy for work that never started and a customer told nothing.
 * Here that would be a courier holding a delivery no restaurant knows about.
 *
 * <p>Structural rather than behavioural, deliberately — reproducing it needs a
 * real transaction manager, a real commit and a real publisher, none of which
 * exist on this machine, which is exactly why it reached production. What can be
 * checked is the rule: reachable from a listener, and it writes, therefore
 * {@code REQUIRES_NEW}.
 */
class CourierListenerTransactionTests {

    private static final List<String> CALLED_FROM_A_LISTENER =
        List.of("courierAssigned", "courierSearchFailed");

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
        // and wrong — and would put a courier on an order off an assignment
        // whose transaction then rolls back.
        assertThat(Arrays.stream(CourierDispatchListener.class.getDeclaredMethods())
            .filter(m -> m.isAnnotationPresent(TransactionalEventListener.class))
            .map(m -> m.getAnnotation(TransactionalEventListener.class).phase()))
            .isNotEmpty()
            .allMatch(phase -> phase == TransactionPhase.AFTER_COMMIT);
    }

    private static Method methodNamed(String name) {
        return Arrays.stream(OrderFulfilmentService.class.getDeclaredMethods())
            .filter(m -> m.getName().equals(name))
            .findFirst()
            .orElseThrow(() -> new AssertionError(
                "OrderFulfilmentService." + name + " is gone — this test needs updating"));
    }
}
