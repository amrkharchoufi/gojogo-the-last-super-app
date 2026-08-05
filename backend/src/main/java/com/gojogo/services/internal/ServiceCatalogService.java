package com.gojogo.services.internal;

import com.gojogo.media.MediaApi;
import com.gojogo.payments.WalletApi;
import com.gojogo.services.ServiceUpserted;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/** The provider's catalog and profile, and the public browse over both. */
@Service
class ServiceCatalogService {

    private final ServiceOfferingRepository offerings;
    private final ProviderRepository providers;
    private final ProviderDirectory directory;
    private final MediaApi media;
    private final WalletApi wallet;
    private final ApplicationEventPublisher events;

    ServiceCatalogService(ServiceOfferingRepository offerings, ProviderRepository providers,
                          ProviderDirectory directory, MediaApi media, WalletApi wallet,
                          ApplicationEventPublisher events) {
        this.offerings = offerings;
        this.providers = providers;
        this.directory = directory;
        this.media = media;
        this.wallet = wallet;
        this.events = events;
    }

    // MARK: Provider profile

    @Transactional
    ServiceDtos.ProviderResponse updateProfile(UUID ownerUserId,
                                               ServiceDtos.UpdateProviderRequest request) {
        Provider provider = directory.requireMine(ownerUserId);
        try {
            provider.configure(request.displayName().trim(), request.logoUrl(), request.bio(),
                request.qualifications(), request.serviceAreas(), request.languages(),
                request.timezone());
        } catch (java.time.DateTimeException badZone) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Unknown timezone " + request.timezone());
        }
        List<String> portfolio = request.portfolioUrls() == null ? List.of()
            : request.portfolioUrls().stream().filter(u -> u != null && !u.isBlank()).toList();
        provider.replacePortfolio(portfolio);
        Provider saved = providers.save(provider);
        if (!portfolio.isEmpty()) {
            media.markReferenced(portfolio);
        }
        return toProviderResponse(saved);
    }

    @Transactional(readOnly = true)
    ServiceDtos.ProviderResponse mine(UUID ownerUserId) {
        return toProviderResponse(directory.requireMine(ownerUserId));
    }

    /** The public profile — a suspended provider 404s like one that never was. */
    @Transactional(readOnly = true)
    ServiceDtos.ProviderResponse publicProfile(UUID providerId) {
        Provider provider = directory.require(providerId);
        if (provider.isSuspended()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such provider");
        }
        return toProviderResponse(provider);
    }

    // MARK: Catalog

    @Transactional
    ServiceDtos.ServiceResponse create(UUID ownerUserId, ServiceDtos.ServiceRequest request) {
        Provider provider = directory.requireMine(ownerUserId);
        ServiceOffering offering = new ServiceOffering(provider.getId(), request.name().trim(),
            request.description(), blankTo(request.category(), "General"),
            request.durationMinutes(), request.priceCents(),
            parseLocation(request.locationKind()), request.requirements());
        ServiceOffering saved = offerings.save(offering);
        publishUpserted(saved);
        return toResponse(saved, provider);
    }

    @Transactional
    ServiceDtos.ServiceResponse update(UUID ownerUserId, UUID serviceId,
                                       ServiceDtos.ServiceRequest request) {
        Provider provider = directory.requireMine(ownerUserId);
        ServiceOffering offering = owned(provider, serviceId);
        offering.edit(request.name().trim(), request.description(),
            blankTo(request.category(), "General"), request.durationMinutes(),
            request.priceCents(), parseLocation(request.locationKind()),
            request.requirements());
        ServiceOffering saved = offerings.save(offering);
        publishUpserted(saved);
        return toResponse(saved, provider);
    }

    @Transactional
    ServiceDtos.ServiceResponse setActive(UUID ownerUserId, UUID serviceId, boolean active) {
        Provider provider = directory.requireMine(ownerUserId);
        ServiceOffering offering = owned(provider, serviceId);
        offering.setActive(active);
        ServiceOffering saved = offerings.save(offering);
        publishUpserted(saved);
        return toResponse(saved, provider);
    }

    @Transactional(readOnly = true)
    List<ServiceDtos.ServiceResponse> mineCatalog(UUID ownerUserId, int limit) {
        Provider provider = directory.requireMine(ownerUserId);
        return offerings.findByProviderIdOrderByCreatedAtDesc(provider.getId(),
                PageRequest.of(0, Math.clamp(limit, 1, 100))).stream()
            .map(s -> toResponse(s, provider))
            .toList();
    }

    @Transactional(readOnly = true)
    ServiceDtos.ServicePageResponse browse(String category, UUID providerId,
                                           OffsetDateTime before, int limit) {
        OffsetDateTime cursor = before == null ? OffsetDateTime.now().plusMinutes(1) : before;
        int size = Math.clamp(limit, 1, 50);
        String cat = category == null || category.isBlank() || category.equalsIgnoreCase("All")
            ? null : category;
        List<ServiceOffering> page = offerings.browse(cat, providerId, cursor,
            PageRequest.of(0, size));
        Map<UUID, Provider> byId = providers.findAllById(page.stream()
                .map(ServiceOffering::getProviderId).collect(Collectors.toSet())).stream()
            .collect(Collectors.toMap(Provider::getId, p -> p));
        List<ServiceDtos.ServiceResponse> items = page.stream()
            .map(s -> toResponse(s, byId.get(s.getProviderId())))
            .toList();
        OffsetDateTime nextBefore = page.size() < size ? null : page.getLast().getCreatedAt();
        return new ServiceDtos.ServicePageResponse(items, nextBefore);
    }

    @Transactional(readOnly = true)
    ServiceDtos.ServiceResponse get(UUID me, UUID serviceId) {
        ServiceOffering offering = offerings.findById(serviceId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such service"));
        Provider provider = directory.require(offering.getProviderId());
        boolean owner = provider.getOwnerUserId().equals(me);
        if (!owner && (!offering.isBrowsable() || provider.isSuspended())) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such service");
        }
        return toResponse(offering, provider);
    }

    ServiceOffering owned(Provider provider, UUID serviceId) {
        ServiceOffering offering = offerings.findById(serviceId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such service"));
        if (!offering.getProviderId().equals(provider.getId())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your service");
        }
        return offering;
    }

    private void publishUpserted(ServiceOffering offering) {
        events.publishEvent(new ServiceUpserted(offering.getId(), offering.getProviderId(),
            offering.getName(), offering.getCategory(), offering.isBrowsable(),
            OffsetDateTime.now()));
    }

    ServiceDtos.ServiceResponse toResponse(ServiceOffering s, Provider provider) {
        return new ServiceDtos.ServiceResponse(s.getId(), s.getProviderId(),
            provider == null ? "Provider" : provider.getDisplayName(),
            provider == null ? null : provider.getLogoUrl(),
            s.getName(), s.getDescription(), s.getCategory(), s.getDurationMinutes(),
            s.getPriceCents(), s.isQuoted(), wallet.currency(),
            s.getLocationKind().name(), s.getRequirements(), s.isActive(),
            s.getRatingCount() == 0 ? null
                : Math.round(s.getRatingSum() * 10.0 / s.getRatingCount()) / 10.0,
            s.getRatingCount(), s.getCreatedAt());
    }

    private ServiceDtos.ProviderResponse toProviderResponse(Provider p) {
        return new ServiceDtos.ProviderResponse(p.getId(), p.getDisplayName(), p.getLogoUrl(),
            p.getBio(), p.getQualifications(), p.getServiceAreas(), p.getLanguages(),
            p.getTimezone(),
            p.getPortfolio().stream().map(ProviderMedia::getImageUrl).toList(),
            p.isSuspended(), p.getCreatedAt());
    }

    private static LocationKind parseLocation(String value) {
        if (value == null || value.isBlank()) return LocationKind.AT_PROVIDER;
        try {
            return LocationKind.valueOf(value.trim().toUpperCase());
        } catch (IllegalArgumentException unknown) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Unknown location kind " + value);
        }
    }

    private static String blankTo(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }
}
