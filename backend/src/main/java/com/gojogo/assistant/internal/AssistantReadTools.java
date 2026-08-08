package com.gojogo.assistant.internal;

import com.fasterxml.jackson.databind.JsonNode;
import com.gojogo.delivery.DeliveryCatalogApi;
import com.gojogo.economy.MarketplaceApi;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.WalletApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import com.gojogo.search.SearchKind;
import com.gojogo.search.SearchQueryApi;
import com.gojogo.services.BookingDirectoryApi;
import com.gojogo.travel.TravelApi;
import org.springframework.stereotype.Component;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * The READ half of MADELEINE.md §5's catalog: ten tools, each reaching its
 * vertical through that vertical's public facade.
 *
 * <p><b>Never a repository, never a controller, never an elevated identity.</b>
 * Every call below passes {@code context.userId()}, so Madeleine sees exactly
 * what the person she is working for would see — a blocked seller's listing is
 * absent for her too, and a ride belonging to somebody else is not found. The
 * facades enforce that, not this class, which is the point of going through
 * them: the vertical stays the owner of its own rules.
 *
 * <p>Three tools needed a facade verb that did not exist yet, and the verb was
 * added to the facade rather than worked around here — {@code SearchQueryApi},
 * {@code DeliveryCatalogApi}, {@code TravelApi}, {@code MarketplaceApi} and
 * {@code BookingDirectoryApi} are all new for this milestone and all usable by
 * anybody.
 *
 * <p>Results are small on purpose. §4 trims lists to {@code toolResultMaxItems}
 * before they enter context, so a tool that returns fifty rows is fifty rows
 * thrown away after being paid for; each handler asks for roughly what survives.
 */
@Component
class AssistantReadTools {

    /**
     * Tools whose result can carry text a user wrote, and which must therefore
     * be wrapped in {@code <user_content>} before entering context (§4).
     *
     * <p>An explicit list rather than "wrap everything", because the delimiter
     * means something: it marks the bytes a stranger controls. {@code get_wallet}
     * and {@code quote_ride} return numbers this platform computed, and marking
     * those as untrusted would teach the model that the marking is decorative.
     *
     * <p>The delimiter is only the first fence in any case. The real defence is
     * that a hostile listing can at worst make Madeleine <em>propose</em> an
     * action, and every consequential action dead-ends at a confirm card.
     */
    private static final java.util.Set<String> USER_AUTHORED = java.util.Set.of(
        "search_all", "get_profile", "search_restaurants", "get_menu",
        "search_listings", "get_listing", "get_ride_status", "get_my_bookings");

    private final SearchQueryApi search;
    private final ProfileApi profiles;
    private final DeliveryCatalogApi delivery;
    private final TravelApi travel;
    private final WalletApi wallet;
    private final MarketplaceApi marketplace;
    private final BookingDirectoryApi bookings;
    private final AssistantPlaceResolver places;

    AssistantReadTools(SearchQueryApi search, ProfileApi profiles, DeliveryCatalogApi delivery,
                       TravelApi travel, WalletApi wallet, MarketplaceApi marketplace,
                       BookingDirectoryApi bookings, AssistantPlaceResolver places) {
        this.search = search;
        this.profiles = profiles;
        this.delivery = delivery;
        this.travel = travel;
        this.wallet = wallet;
        this.marketplace = marketplace;
        this.bookings = bookings;
        this.places = places;
    }

    boolean carriesUserAuthoredText(String toolName) {
        return USER_AUTHORED.contains(toolName);
    }

    /** Name → implementation, for the registry to match against the catalog. */
    Map<String, AssistantToolHandler> handlers() {
        Map<String, AssistantToolHandler> handlers = new LinkedHashMap<>();
        handlers.put("search_all", this::searchAll);
        handlers.put("get_profile", this::getProfile);
        handlers.put("search_restaurants", this::searchRestaurants);
        handlers.put("get_menu", this::getMenu);
        handlers.put("quote_ride", this::quoteRide);
        handlers.put("get_ride_status", this::getRideStatus);
        handlers.put("get_wallet", this::getWallet);
        handlers.put("search_listings", this::searchListings);
        handlers.put("get_listing", this::getListing);
        handlers.put("get_my_bookings", this::getMyBookings);
        return handlers;
    }

    // MARK: search

    /**
     * Federated search — the primary entry point when intent is not yet narrowed.
     *
     * <p>Three sources, because the index does not cover everything: restaurants
     * and people are not {@link SearchKind}s, so they are queried at their own
     * modules and merged in. Restaurants lead an unfiltered search on purpose —
     * they are invisible to the index, and a hungry person asking "couscous"
     * would otherwise get marketplace rows and nothing to eat.
     */
    private Object searchAll(AssistantToolContext context, JsonNode args) {
        String query = text(args, "query");
        String kind = text(args, "kind").toUpperCase(Locale.ROOT);
        List<Map<String, Object>> results = new ArrayList<>();

        boolean any = kind.isBlank() || kind.equals("ANY");
        if (any || kind.equals("RESTAURANT")) {
            delivery.searchRestaurants(query, null, any ? 4 : 8).forEach(r ->
                results.add(ordered("kind", "RESTAURANT", "id", r.id(), "name", r.name(),
                    "cuisine", r.cuisine(), "rating", r.rating(),
                    "deliveryMinutes", r.etaMinutes(), "openNow", r.openNow())));
        }
        if (any || kind.equals("PROFILE")) {
            profiles.search(query, any ? 3 : 8).forEach(p ->
                results.add(ordered("kind", "PROFILE", "id", p.id(), "name", p.displayName(),
                    "handle", p.handle())));
        }
        SearchKind indexKind = indexKind(kind);
        if (any || indexKind != null) {
            search.search(query, indexKind, 8).forEach(hit ->
                results.add(ordered("kind", hit.kind().name(), "id", hit.refId(),
                    "name", hit.title(), "detail", hit.snippet(),
                    "category", hit.category())));
        }
        return Map.of("results", results);
    }

    /** The tool's enum is wider than the index's; the extras are served above. */
    private static SearchKind indexKind(String kind) {
        return switch (kind) {
            case "LISTING" -> SearchKind.LISTING;
            case "SERVICE" -> SearchKind.SERVICE;
            case "POST" -> SearchKind.POST;
            default -> null;
        };
    }

    // MARK: profile

    private Object getProfile(AssistantToolContext context, JsonNode args) {
        Optional<ProfileDto> profile = profiles.findById(context.userId());
        if (profile.isEmpty()) {
            return Map.of("error", "NO_PROFILE");
        }
        ProfileDto me = profile.get();
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("handle", me.handle());
        result.put("displayName", me.displayName());
        // The default delivery address is the only "where do you live" this
        // platform holds, and delivery owns it. Absent is a real answer: a user
        // who has never ordered has no address, and a tool that invented one
        // would send dinner to a guess.
        delivery.defaultAddressOf(context.userId()).ifPresent(address -> {
            result.put("defaultAddressId", address.id());
            result.put("defaultAddress", address.line1());
            result.put("defaultAddressLabel", address.label());
        });
        return result;
    }

    // MARK: delivery

    private Object searchRestaurants(AssistantToolContext context, JsonNode args) {
        Integer maxMinutes = args.hasNonNull("maxDeliveryMinutes")
            ? args.get("maxDeliveryMinutes").asInt() : null;
        List<Map<String, Object>> restaurants =
            delivery.searchRestaurants(text(args, "query"), maxMinutes, 8).stream()
                .map(r -> ordered("id", r.id(), "name", r.name(), "cuisine", r.cuisine(),
                    "rating", r.rating(), "deliveryMinutes", r.etaMinutes(),
                    "deliveryFeeMinor", r.deliveryFeeMinor(), "currency", wallet.currency(),
                    "openNow", r.openNow()))
                .toList();
        return Map.of("restaurants", restaurants);
    }

    private Object getMenu(AssistantToolContext context, JsonNode args) {
        UUID restaurantId = uuid(args, "restaurantId");
        if (restaurantId == null) {
            return badId("restaurantId", text(args, "restaurantId"));
        }
        return delivery.menu(restaurantId)
            .<Object>map(menu -> Map.of(
                "restaurantId", menu.restaurantId(),
                "restaurantName", menu.restaurantName(),
                "currency", wallet.currency(),
                "items", menu.items().stream()
                    .map(i -> ordered("id", i.id(), "name", i.name(), "detail", i.detail(),
                        "priceMinor", i.priceMinor(), "popular", i.popular()))
                    .toList()))
            .orElseGet(() -> Map.of("error", "NOT_FOUND", "restaurantId", restaurantId));
    }

    // MARK: travel

    private Object quoteRide(AssistantToolContext context, JsonNode args) {
        Optional<AssistantPlaceResolver.Place> from =
            places.resolve(context.userId(), text(args, "fromText"));
        Optional<AssistantPlaceResolver.Place> to =
            places.resolve(context.userId(), text(args, "toText"));
        if (from.isEmpty() || to.isEmpty()) {
            // Naming what could not be resolved, and what could have been, is
            // what lets the model ask a useful question instead of guessing a
            // coordinate. There is no geocoder to fall back to.
            return ordered(
                "error", "UNRESOLVED_PLACE",
                "unresolved", from.isEmpty() ? text(args, "fromText") : text(args, "toText"),
                "knownPlaces", places.knownPlaces(context.userId()),
                "hint", "Only the user's saved addresses can be resolved to a point. "
                    + "Ask them which saved place they mean, or to pick the spot on the map.");
        }
        TravelApi.Quote quote = travel.quote(from.get().latitude(), from.get().longitude(),
            to.get().latitude(), to.get().longitude());
        return ordered(
            "from", from.get().label(),
            "to", to.get().label(),
            "distanceMetres", quote.distanceMetres(),
            "durationSeconds", quote.durationSeconds(),
            "currency", quote.currency(),
            "categories", quote.categories().stream()
                .map(c -> ordered("category", c.category(),
                    "suggestedFareMinor", c.suggestedFareMinor(),
                    "minimumMinor", c.minimumMinor()))
                .toList());
    }

    private Object getRideStatus(AssistantToolContext context, JsonNode args) {
        return travel.currentRide(context.userId(), true)
            .<Object>map(ride -> ordered(
                "rideId", ride.id(),
                "state", ride.state(),
                "category", ride.category(),
                "from", ride.pickupLabel(),
                "to", ride.dropoffLabel(),
                "fareMinor", ride.agreedFareMinor() == null
                    ? ride.suggestedFareMinor() : ride.agreedFareMinor(),
                "fareAgreed", ride.agreedFareMinor() != null,
                "currency", ride.currency(),
                "driverName", ride.driverName(),
                "vehicle", ride.vehicleLabel()))
            .orElseGet(() -> Map.of("ride", "NONE"));
    }

    // MARK: money

    private Object getWallet(AssistantToolContext context, JsonNode args) {
        WalletApi.Balances balances = wallet.balancesOf(OwnerKind.USER, context.userId());
        // Spendable and held, and nothing else. There are no wallet write tools
        // at all (§5): a top-up is Stripe-hosted checkout, a human-only surface,
        // so the honest thing for Madeleine to do with a short balance is say so
        // and hand over to the app.
        return ordered(
            "balanceMinor", balances.spendable(),
            "heldMinor", balances.escrow(),
            "currency", balances.currency());
    }

    // MARK: marketplace

    private Object searchListings(AssistantToolContext context, JsonNode args) {
        Long maxPriceMinor = args.hasNonNull("maxPriceMinor")
            ? args.get("maxPriceMinor").asLong() : null;
        // Over-fetch from the index because the price filter runs after
        // hydration — the index stores text and popularity, not prices.
        List<UUID> ids = search.search(text(args, "query"), SearchKind.LISTING, 24).stream()
            .map(SearchQueryApi.Hit::refId)
            .toList();
        List<Map<String, Object>> listings =
            marketplace.listingsByIds(context.userId(), ids).stream()
                .filter(l -> maxPriceMinor == null
                    || (l.priceMinor() != null && l.priceMinor() <= maxPriceMinor))
                .limit(8)
                .map(l -> ordered("id", l.id(), "title", l.title(),
                    "priceMinor", l.priceMinor(), "currency", l.currency(),
                    "city", l.locationLabel(), "condition", l.condition()))
                .toList();
        return Map.of("listings", listings);
    }

    private Object getListing(AssistantToolContext context, JsonNode args) {
        UUID listingId = uuid(args, "listingId");
        if (listingId == null) {
            return badId("listingId", text(args, "listingId"));
        }
        return marketplace.listing(context.userId(), listingId)
            .<Object>map(l -> ordered("id", l.id(), "title", l.title(),
                "priceMinor", l.priceMinor(), "currency", l.currency(),
                "category", l.category(), "condition", l.condition(),
                "city", l.locationLabel(), "description", l.description(),
                "sellerHandle", l.sellerHandle(), "status", l.status()))
            .orElseGet(() -> Map.of("error", "NOT_FOUND", "listingId", listingId));
    }

    // MARK: services

    private Object getMyBookings(AssistantToolContext context, JsonNode args) {
        List<Map<String, Object>> upcoming = bookings.upcomingFor(context.userId(), 8).stream()
            .map(b -> ordered("id", b.id(), "service", b.serviceName(),
                "provider", b.providerName(), "status", b.status(),
                "startsAt", b.startsAt() == null ? null : b.startsAt().toString(),
                "durationMinutes", b.durationMinutes(),
                "priceMinor", b.priceMinor(), "currency", b.currency()))
            .toList();
        return Map.of("bookings", upcoming, "asOf", OffsetDateTime.now().toString());
    }

    // MARK: argument reading
    //
    // Lenient on shape, strict on meaning. A model that sends an integer where a
    // string was asked for should still get an answer; a model that sends a
    // restaurant name where an id was asked for must not, because "no such
    // restaurant" would be a lie about the catalog rather than about the call.

    private static String text(JsonNode args, String field) {
        JsonNode value = args.get(field);
        return value == null || value.isNull() ? "" : value.asText("");
    }

    private static UUID uuid(JsonNode args, String field) {
        try {
            return UUID.fromString(text(args, field).strip());
        } catch (IllegalArgumentException notAnId) {
            return null;
        }
    }

    private static Map<String, Object> badId(String field, String got) {
        return ordered("error", "BAD_ARGUMENT", "field", field, "got", got,
            "hint", "This must be an id returned by an earlier tool call, not a name.");
    }

    /** {@code Map.of} rejects nulls and reorders; a tool result wants neither. */
    private static Map<String, Object> ordered(Object... keysAndValues) {
        Map<String, Object> map = new LinkedHashMap<>();
        for (int i = 0; i + 1 < keysAndValues.length; i += 2) {
            map.put((String) keysAndValues[i], keysAndValues[i + 1]);
        }
        return map;
    }
}
