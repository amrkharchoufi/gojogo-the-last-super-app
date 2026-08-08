package com.gojogo.assistant.internal;

/**
 * What a tool is allowed to do (MADELEINE.md §5).
 *
 * <p><b>The classification is the security model.</b> It is not advice to the
 * model and not a note for a reviewer: {@code AssistantToolExecutor} switches on
 * it, and the branch that would call a vertical for a {@code WRITE_GATED} tool
 * does not exist. That is the difference between a rule a prompt can be talked
 * out of and a rule that is simply not implemented.
 */
enum AssistantToolClass {

    /** Reads. Execute immediately, in parallel where independent. */
    READ,

    /**
     * Reversible, and stays in the user's private space — a cart, a draft, a
     * prefilled composer. Executes without a card because undoing it is one tap
     * and nobody outside can see it.
     */
    WRITE_SAFE,

    /**
     * Moves money or leaves the user's private space. <b>Never executes from
     * model output.</b> The executor writes an {@code AssistantAction} carrying
     * a confirm token the model is never shown, and the user's approval is the
     * only thing that can turn it into a vertical call — one action, one
     * approval, no batching, no "always allow".
     */
    WRITE_GATED,

    /** Runs on the phone (§6): navigate, prefill, highlight. Never a tap. */
    CLIENT
}
