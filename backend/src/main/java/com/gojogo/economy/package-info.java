/**
 * Economy module — marketplace listings, sell flow, and saves
 * ({@code economy} schema). A vertical product surface (ARCHITECTURE.md §2/§6):
 * owns its listing data, decorates sellers via the {@code profile} public API,
 * marks listing images referenced via {@code media}, and publishes
 * {@link com.gojogo.economy.ListingCreated} for future search indexing.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Economy")
package com.gojogo.economy;
