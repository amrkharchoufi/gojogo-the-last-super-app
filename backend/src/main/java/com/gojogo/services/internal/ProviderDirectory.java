package com.gojogo.services.internal;

import com.gojogo.services.ProviderProvisioningApi;
import com.gojogo.services.ProviderRegistration;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.UUID;

/** The provisioning door and the owner-scoped lookup the /mine surface starts
 *  from — {@code SellerRegistry}'s shape, one vertical over. */
@Service
class ProviderDirectory implements ProviderProvisioningApi {

    private final ProviderRepository providers;

    ProviderDirectory(ProviderRepository providers) {
        this.providers = providers;
    }

    @Override
    @Transactional
    public UUID provisionProvider(ProviderRegistration registration) {
        return providers.findByOwnerUserId(registration.ownerUserId())
            .map(Provider::getId)
            .orElseGet(() -> providers.save(new Provider(registration.ownerUserId(),
                registration.displayName(), registration.logoUrl())).getId());
    }

    @Override
    @Transactional
    public void setProviderSuspended(UUID providerId, boolean suspended) {
        providers.findById(providerId).ifPresent(provider -> {
            provider.setSuspended(suspended);
            providers.save(provider);
        });
    }

    Provider requireMine(UUID ownerUserId) {
        return providers.findByOwnerUserId(ownerUserId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "You don't have a provider profile"));
    }

    Provider require(UUID providerId) {
        return providers.findById(providerId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such provider"));
    }
}
