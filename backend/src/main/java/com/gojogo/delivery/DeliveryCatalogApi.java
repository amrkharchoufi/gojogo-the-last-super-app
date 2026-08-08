package com.gojogo.delivery;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * The read side of the delivery vertical, for other modules.
 *
 * <p>{@link MerchantProvisioningApi} is how a restaurant comes into existence;
 * this is how somebody who is not the customer's phone asks what is on the
 * menu. Added for Madeleine's {@code search_restaurants} / {@code get_menu}
 * tools (MADELEINE.md §5), which reach every vertical through its facade and
 * never through its repositories — but nothing here is assistant-shaped, and a
 * second reader would use it unchanged.
 *
 * <p>Read-only by construction: there is no cart verb and no order verb here.
 * Placing an order charges a wallet, and that path stays where its rules live —
 * behind {@code /v1/delivery/orders}, with the customer's own identity on it.
 *
 * <p>Money is integer minor units, as everywhere (the {@code Cents} suffix the
 * module's own DTOs carry is the same unit under an older name).
 */
public interface DeliveryCatalogApi {

    /**
     * Restaurants matching free text, best first, using the same catalog query
     * the browse screen runs.
     *
     * @param maxDeliveryMinutes null for no ETA filter. Applied after the
     *                           catalog query rather than inside it, because
     *                           the ETA a card shows is derived, not a column
     *                           the browse index can filter on.
     * @param limit              clamped to 1..50
     */
    List<Restaurant> searchRestaurants(String query, Integer maxDeliveryMinutes, int limit);

    /** One restaurant with its menu, or empty if there is no such restaurant. */
    Optional<Menu> menu(UUID restaurantId);

    /**
     * The user's saved delivery addresses, default first.
     *
     * <p>Delivery owns addresses (they arrived with the vertical and carry its
     * coordinates), so anyone who needs to know where somebody lives asks here
     * rather than growing a second copy — the same reason emergency contacts
     * live on {@code ProfileApi} rather than in {@code travel}.
     */
    List<SavedAddress> addressesOf(UUID userId);

    /** The address an order would go to unless the user picks another. */
    Optional<SavedAddress> defaultAddressOf(UUID userId);

    /** A browse card: what a chooser needs, and nothing a page would need. */
    record Restaurant(UUID id, String name, String cuisine, double rating, int etaMinutes,
                      long deliveryFeeMinor, boolean openNow) {
    }

    /** One restaurant's menu, flattened out of its sections — a caller picking
     *  a dish wants dishes, and the sections are a layout of the app's page. */
    record Menu(UUID restaurantId, String restaurantName, List<MenuEntry> items) {
    }

    record MenuEntry(UUID id, String name, String detail, long priceMinor, boolean popular) {
    }

    record SavedAddress(UUID id, String label, String line1, Double latitude, Double longitude,
                        boolean isDefault) {
    }
}
