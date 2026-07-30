package com.gojogo.profile;

/**
 * What a profile <em>is</em>. A business is a profile (ARCHITECTURE.md §2b
 * decision 1), so this is a field rather than a second table with its own
 * social graph — a follow is a follow whichever kind is on either end.
 */
public enum ProfileKind {
    PERSON,
    BUSINESS
}
