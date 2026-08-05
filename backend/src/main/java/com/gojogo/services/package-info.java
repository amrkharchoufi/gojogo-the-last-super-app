/**
 * Services module — the bookable-services vertical ({@code services} schema,
 * Phase 5 M3, SPECS §7). Provider profiles with portfolios and private
 * qualification papers, a catalog of services with durations and location
 * kinds, a weekly availability template with exceptions, and the booking state
 * machine: {@code REQUESTED → CONFIRMED → COMPLETED | DECLINED |
 * CANCELLED_CUSTOMER | CANCELLED_PROVIDER | NO_SHOW}.
 *
 * <p>Providers arrive through
 * {@link com.gojogo.services.ProviderProvisioningApi} — {@code partner} creates
 * what a {@code SERVICE_PROVIDER} approval earns and never runs the practice.
 * Money is the wallet's ({@code hold} at request or quote-acceptance,
 * settlement after completion, commission via {@code FeeApi.SERVICES});
 * conversation is {@code messaging}'s, stamped with a
 * {@code ConversationContext(kind="booking")} card; qualification papers ride
 * {@code MediaDocumentApi}'s private prefix.
 *
 * <p>Publishes {@link com.gojogo.services.ServiceUpserted} for search (Phase 5
 * M4) and the booking events the notifications matrix names (requested,
 * confirmed, reminders).
 */
@org.springframework.modulith.ApplicationModule(displayName = "Services")
package com.gojogo.services;
