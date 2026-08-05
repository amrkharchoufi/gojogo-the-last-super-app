package com.gojogo.economy.internal;

import com.gojogo.economy.SellerProvisioningApi;
import com.gojogo.economy.SellerRegistration;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.UUID;

/**
 * The provisioning door ({@code SellerProvisioningApi}) and the owner-scoped
 * seller lookup everything on the {@code /mine} surface starts from.
 */
@Service
class SellerRegistry implements SellerProvisioningApi {

    private final SellerRepository sellers;

    SellerRegistry(SellerRepository sellers) {
        this.sellers = sellers;
    }

    @Override
    @Transactional
    public UUID provisionSeller(SellerRegistration registration) {
        return sellers.findByOwnerUserId(registration.ownerUserId())
            .map(Seller::getId)
            .orElseGet(() -> sellers.save(new Seller(registration.ownerUserId(),
                registration.displayName(), registration.logoUrl())).getId());
    }

    @Override
    @Transactional
    public void setSellerSuspended(UUID sellerId, boolean suspended) {
        sellers.findById(sellerId).ifPresent(seller -> {
            seller.setSuspended(suspended);
            sellers.save(seller);
        });
    }

    /** The caller's shop, or a 404 that reads the same whether they never had
     *  one or mistyped — provisioning is partner's business, not this surface's. */
    Seller requireMine(UUID ownerUserId) {
        return sellers.findByOwnerUserId(ownerUserId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "You don't have a seller shop"));
    }

    Seller require(UUID sellerId) {
        return sellers.findById(sellerId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such seller"));
    }
}
