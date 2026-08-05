package com.gojogo.search;

/**
 * What can be found. The SPECS §13 list, minus the kinds whose modules don't
 * publish an upsert signal yet (merchants, menu items, videos, business
 * profiles) — a kind lands here the day its module publishes one and registers
 * a {@link SearchableContent}.
 */
public enum SearchKind {
    POST,
    LISTING,
    PRODUCT,
    SERVICE
}
