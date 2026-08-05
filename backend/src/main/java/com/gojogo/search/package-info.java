/**
 * Search module — the unified index and query surface (Phase 5 M4, SPECS §13).
 * A platform capability: it owns the pipeline and the ranking, and knows
 * nothing about any vertical.
 *
 * <p>The direction is the established plugin shape ({@code ConversationGuard} /
 * {@code ModeratableContent} / {@code ShareableResource} /
 * {@code StorefrontReferenceCheck} — this is the fifth instance), on both
 * sides of the seam. A vertical listens to <em>its own</em> events and calls
 * {@link com.gojogo.search.SearchIndexApi#reindex}; this module then asks the
 * {@link com.gojogo.search.SearchableContent} bean registered for that kind to
 * render the document. A kind with no provider on the classpath is simply not
 * indexed, and search imports nothing from any vertical — which is what keeps
 * the module graph acyclic. Each module owns its document shape; this one owns
 * only the store and the query.
 *
 * <p>The store is a Postgres tsvector table, not the OpenSearch domain SPECS
 * names — no domain exists in the deployed infra, and a search that works
 * unconfigured beats a search waiting on a cluster (the KYC posture). The
 * repository is the seam an OpenSearch client replaces, behind the same API,
 * whenever that infra decision is taken.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Search")
package com.gojogo.search;
