package com.gojogo.assistant.internal;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * The two thread pools Madeleine runs on.
 *
 * <p>Both are virtual-thread pools: every task in them is dominated by waiting —
 * on a model that takes seconds, on a facade that takes milliseconds — and
 * platform threads sized for that would be either an idle wall of stacks or a
 * queue behind sixteen of them.
 *
 * <p>They are separate on purpose. A turn occupies its thread for its whole
 * lifetime and fans its tool calls out into the other pool; sharing one would
 * let a burst of turns starve the very calls those turns are blocked on, which
 * is a deadlock wearing a latency graph.
 *
 * <p>Spring's inferred {@code shutdown()} on context close is the behaviour we
 * want on a rolling deploy: already-running turns finish their in-flight step
 * and write their ledger rows, and nothing new is accepted. An interrupt here
 * would leave a half-recorded turn, which is the one state the ledger must not
 * have.
 */
@Configuration
class AssistantExecutors {

    /** Runs whole turns, detached from the HTTP request that started them. */
    @Bean
    ExecutorService assistantTurnPool() {
        return Executors.newThreadPerTaskExecutor(
            Thread.ofVirtual().name("madeleine-turn-", 0).factory());
    }

    /** Runs the READ tool calls of one model response in parallel (§4 step 3). */
    @Bean
    ExecutorService assistantToolPool() {
        return Executors.newThreadPerTaskExecutor(
            Thread.ofVirtual().name("madeleine-tool-", 0).factory());
    }
}
