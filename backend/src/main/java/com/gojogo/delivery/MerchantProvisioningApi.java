package com.gojogo.delivery;

import java.util.UUID;

/**
 * Public API of the delivery module: how an approved partner becomes a
 * restaurant in the catalog.
 *
 * <p>Deliberately narrow, in the same spirit as {@code MessagingApi} and
 * {@code MusicApi}. The {@code partner} module owns the application and the KYC
 * review; it does not get to run the catalog. It can create the merchant an
 * approval earns and switch it off again if the partnership ends — everything
 * after that (menu, prices, opening the restaurant to buyers) belongs to the
 * owner, over delivery's own owner-scoped REST surface.
 *
 * <p>A provisioned merchant starts <em>hidden</em>. A restaurant with no dishes
 * on it is worse than no restaurant at all, so the owner publishes it once the
 * menu exists; delivery enforces that, not the caller.
 */
public interface MerchantProvisioningApi {

    /**
     * Creates the merchant for a newly approved partner and returns its id, or
     * returns the id of the one they already own. Idempotent, so a retried
     * approval cannot leave a partner with two restaurants.
     */
    UUID provisionMerchant(MerchantRegistration registration);

    /**
     * Takes a merchant out of the catalog, or puts it back. Called when a
     * partnership is suspended or restored — a suspended partner's restaurant
     * must stop taking orders without their menu being deleted.
     *
     * <p>Restoring only clears the block: a merchant the owner had not yet
     * published stays unpublished.
     */
    void setMerchantSuspended(UUID merchantId, boolean suspended);
}
