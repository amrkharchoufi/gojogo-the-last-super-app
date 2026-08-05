package com.gojogo.services;

import java.util.UUID;

/**
 * Public API of the services module: how an approved partner becomes a service
 * provider with a bookable catalog.
 *
 * <p>The fourth instance of the provisioning pattern
 * ({@code delivery.MerchantProvisioningApi}, {@code dispatch}'s two,
 * {@code economy.SellerProvisioningApi}), same direction: {@code partner} owns
 * the application and the human review; everything after — the profile, the
 * catalog, availability, bookings — belongs to the owner over this module's own
 * owner-scoped surface.
 */
public interface ProviderProvisioningApi {

    /**
     * Creates the provider for a newly approved partner and returns its id, or
     * returns the id of the one they already own. Idempotent, so a retried
     * approval cannot leave a partner with two practices.
     */
    UUID provisionProvider(ProviderRegistration registration);

    /**
     * Blocks a provider from being found or booked, or lifts the block.
     * Existing bookings survive a suspension — a customer's confirmed
     * appointment is not the platform's to vanish.
     */
    void setProviderSuspended(UUID providerId, boolean suspended);
}
