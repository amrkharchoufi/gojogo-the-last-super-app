package com.gojogo.economy;

import java.util.UUID;

/**
 * Public API of the economy module: how an approved partner becomes a seller
 * with a merchant catalog.
 *
 * <p>The third instance of the provisioning pattern
 * ({@code delivery.MerchantProvisioningApi}, {@code dispatch.DriverProvisioningApi}),
 * and the same direction: {@code partner} owns the application and the human
 * review, and gets to create what an approval earns and to switch it off again.
 * It does not get to run the catalog — products, prices, shipping config and
 * promotions belong to the owner, over economy's own owner-scoped REST surface.
 *
 * <p>A provisioned seller starts with an empty shop, which is fine: a product
 * catalog with nothing in it simply doesn't appear anywhere, so there is no
 * "publish" gate to hold — the catalog is its own gate.
 */
public interface SellerProvisioningApi {

    /**
     * Creates the seller for a newly approved partner and returns its id, or
     * returns the id of the one they already own. Idempotent, so a retried
     * approval cannot leave a partner with two shops.
     */
    UUID provisionSeller(SellerRegistration registration);

    /**
     * Blocks a seller's catalog from being browsed or bought from, or lifts the
     * block. Nothing is deleted — a suspended partner's products stay theirs.
     */
    void setSellerSuspended(UUID sellerId, boolean suspended);
}
