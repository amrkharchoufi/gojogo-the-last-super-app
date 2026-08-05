package com.gojogo.search;

import java.util.Optional;
import java.util.UUID;

/**
 * How a vertical makes its things findable — the fifth instance of the plugin
 * shape ({@code ConversationGuard}, {@code ModeratableContent},
 * {@code WorkerEligibility}, {@code ShareableResource}), and the same
 * direction: the vertical implements, the platform calls.
 *
 * <p>The search module hears the vertical's own event and asks the bean
 * registered for that kind to render the document <em>now</em>, which is what
 * keeps the index honest about edits, hides and deletions: whatever this
 * returns is what the index says, and {@link Optional#empty()} means the thing
 * is gone and so is its row.
 */
public interface SearchableContent {

    SearchKind kind();

    /** The document as it stands right now, or empty if the thing no longer
     *  exists. Called after the vertical's own transaction committed. */
    Optional<SearchDocument> render(UUID refId);
}
