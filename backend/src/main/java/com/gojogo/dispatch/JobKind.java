package com.gojogo.dispatch;

/**
 * What the work is, from dispatch's point of view: a label and nothing more.
 *
 * <p>Deliberately not a hierarchy and deliberately not detailed. Dispatch stores
 * this beside an id it never dereferences; the vertical that published the id
 * owns everything about what it means.
 */
public enum JobKind {

    RIDE,
    DELIVERY
}
