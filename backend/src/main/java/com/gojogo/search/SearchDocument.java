package com.gojogo.search;

import java.util.UUID;

/**
 * What a vertical hands the index for one of its things: the text a query
 * matches, the popularity the ranking multiplies in, and whether it should be
 * findable at all. {@code active=false} keeps the row and hides it — a hidden
 * listing or a paused product leaves the results without leaving the index.
 */
public record SearchDocument(String title, String body, String category, UUID ownerId,
                             long popularity, boolean active) {
}
