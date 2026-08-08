package com.gojogo.assistant.internal;

/*
 * The module's state vocabularies, together because each is a handful of words
 * and the four of them are read as a set (MADELEINE.md §3, §5, §7).
 *
 * Every one is persisted as its own name — @Enumerated(STRING) — so a
 * reordering can never silently reinterpret existing rows.
 */

/** Whether a thread is still on the user's list. */
enum AssistantConversationState {
    ACTIVE,
    ARCHIVED
}

/**
 * Who wrote a ledger row.
 *
 * <p>{@code TOOL} is not the model's voice and not the user's: it is the record
 * that something ran, carrying the trimmed summary that entered context rather
 * than the payload that did not.
 */
enum AssistantMessageRole {
    USER,
    MADELEINE,
    TOOL
}

/** {@code QUEUED → RUNNING → WAITING_APPROVAL → RUNNING → … → DONE | FAILED |
 *  CANCELLED} (§7). The runner that walks it is M6; the states are here so the
 *  ledger and the schema agree from the start. */
enum AssistantTaskState {
    QUEUED,
    RUNNING,
    WAITING_APPROVAL,
    DONE,
    FAILED,
    CANCELLED
}

/**
 * The life of a gated action (§5).
 *
 * <p>M2 only ever writes {@code PENDING} and only ever reads it back to refuse
 * a repeat. {@code APPROVED}/{@code EXECUTED}/{@code DECLINED}/{@code EXPIRED}
 * are M4's, and are declared now because the table that holds them is written
 * now — a state machine that grows a value per milestone is one nobody can
 * reason about.
 */
enum AssistantActionState {
    PENDING,
    APPROVED,
    EXECUTED,
    DECLINED,
    EXPIRED
}
