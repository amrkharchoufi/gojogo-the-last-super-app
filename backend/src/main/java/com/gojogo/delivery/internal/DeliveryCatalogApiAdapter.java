package com.gojogo.delivery.internal;

import com.gojogo.delivery.DeliveryCatalogApi;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * {@link DeliveryCatalogApi} over {@link DeliveryService} — the same catalog
 * query, the same menu assembly and the same address list the customer-facing
 * controller serves, so an in-process reader can never see a different
 * restaurant from the one on the phone.
 */
@Component
class DeliveryCatalogApiAdapter implements DeliveryCatalogApi {

    private final DeliveryService delivery;

    DeliveryCatalogApiAdapter(DeliveryService delivery) {
        this.delivery = delivery;
    }

    @Override
    public List<Restaurant> searchRestaurants(String query, Integer maxDeliveryMinutes, int limit) {
        int size = Math.clamp(limit, 1, 50);
        // Filtering after the query means an ETA filter can return fewer rows
        // than asked for rather than reaching deeper into the catalog. That is
        // the honest shape: "restaurants that deliver within 30 minutes" is a
        // narrowing of what browse found, not a different search.
        return delivery.browse(null, query, size).stream()
            .filter(m -> maxDeliveryMinutes == null || m.etaMinutes() <= maxDeliveryMinutes)
            .map(m -> new Restaurant(m.id(), m.name(), m.cuisine(), m.rating(), m.etaMinutes(),
                m.deliveryFeeCents(), m.openNow()))
            .toList();
    }

    @Override
    public Optional<Menu> menu(UUID restaurantId) {
        MerchantDto merchant;
        try {
            merchant = delivery.merchant(restaurantId);
        } catch (org.springframework.web.server.ResponseStatusException notFound) {
            // The controller's 404 is the right answer to a browser and the
            // wrong one to a caller in-process, which wants to decide for
            // itself what a missing restaurant means.
            return Optional.empty();
        }
        List<MenuEntry> items = merchant.menu().stream()
            .flatMap(section -> section.items().stream())
            .map(i -> new MenuEntry(i.id(), i.name(), i.detail(), i.priceCents(), i.popular()))
            .toList();
        return Optional.of(new Menu(merchant.id(), merchant.name(), items));
    }

    @Override
    public List<SavedAddress> addressesOf(UUID userId) {
        return delivery.addresses(userId).stream()
            .map(a -> new SavedAddress(a.id(), a.label(), a.line1(), a.latitude(), a.longitude(),
                a.isDefault()))
            .toList();
    }

    @Override
    public Optional<SavedAddress> defaultAddressOf(UUID userId) {
        List<SavedAddress> all = addressesOf(userId);
        // addresses() already orders default-first, but a user whose only
        // address was never marked default still has somewhere to eat, so fall
        // back to the first rather than reporting none.
        return all.stream().filter(SavedAddress::isDefault).findFirst()
            .or(() -> all.stream().findFirst());
    }
}
