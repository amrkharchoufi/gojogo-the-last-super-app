package com.gojogo.assistant.internal;

import com.gojogo.delivery.DeliveryCatalogApi;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

/**
 * Turns the words a person uses for a place into a point on the map, or admits
 * that it cannot.
 *
 * <p>This platform has no geocoder — the ride pricing engine takes coordinates,
 * and the only places the backend knows the coordinates of are the addresses the
 * user saved themselves. So "home" and "the office" resolve, and "the airport"
 * does not.
 *
 * <p><b>Failing to resolve is a result, not an error.</b> The alternative is a
 * model that invents a plausible-looking latitude, and a fare quoted for the
 * wrong pickup is worse than no fare — the user acts on a number that was never
 * about their trip. So an unresolved place comes back naming the places that
 * <em>would</em> have worked, which is exactly what the model needs to ask a
 * useful question instead of guessing.
 *
 * <p>Lives in {@code assistant} rather than in {@code travel} because it is a
 * natural-language concern: travel owns fares, and turning "chez moi" into a
 * point is not a fare rule.
 */
@Component
class AssistantPlaceResolver {

    /**
     * Words that mean "the address I would have food sent to", in the launch
     * languages (MADELEINE-INFERENCE.md §9: English, French, Spanish core).
     * Deliberately a short closed list — a fuzzy synonym table here would start
     * resolving places the user did not mean, silently.
     */
    private static final Set<String> HOME_WORDS = Set.of(
        "home", "my home", "my place", "my house", "my address",
        "chez moi", "la maison", "à la maison", "a la maison", "mon adresse",
        "mi casa", "casa", "mi domicilio");

    private final DeliveryCatalogApi delivery;

    AssistantPlaceResolver(DeliveryCatalogApi delivery) {
        this.delivery = delivery;
    }

    /**
     * @return the resolved point, or empty — the caller reports the failure with
     *         {@link #knownPlaces} so the model can ask rather than invent
     */
    Optional<Place> resolve(UUID userId, String text) {
        if (text == null || text.isBlank()) {
            return Optional.empty();
        }
        String needle = normalise(text);
        List<DeliveryCatalogApi.SavedAddress> saved = delivery.addressesOf(userId);

        if (HOME_WORDS.contains(needle)) {
            return saved.stream().filter(a -> a.isDefault()).findFirst()
                .or(() -> saved.stream().findFirst())
                .flatMap(AssistantPlaceResolver::toPlace);
        }
        // Label first — "Office" is what the user called it — then the street
        // line, so "Rue des Orangers" finds the address the user typed it into.
        return saved.stream()
            .filter(a -> matches(needle, a.label()) || matches(needle, a.line1()))
            .findFirst()
            .flatMap(AssistantPlaceResolver::toPlace);
    }

    /** The labels a caller can honestly offer the user as alternatives. */
    List<String> knownPlaces(UUID userId) {
        return delivery.addressesOf(userId).stream()
            .map(a -> a.label() == null || a.label().isBlank() ? a.line1() : a.label())
            .filter(label -> label != null && !label.isBlank())
            .toList();
    }

    private static Optional<Place> toPlace(DeliveryCatalogApi.SavedAddress address) {
        // A saved address without coordinates is real: the app allows a typed
        // line with no map pin. It cannot price a ride, so it is not a place.
        if (address.latitude() == null || address.longitude() == null) {
            return Optional.empty();
        }
        String label = address.label() == null || address.label().isBlank()
            ? address.line1() : address.label();
        return Optional.of(new Place(label, address.latitude(), address.longitude()));
    }

    private static boolean matches(String needle, String candidate) {
        if (candidate == null || candidate.isBlank()) {
            return false;
        }
        String hay = normalise(candidate);
        return hay.equals(needle) || hay.contains(needle) || needle.contains(hay);
    }

    private static String normalise(String value) {
        return value.strip().toLowerCase(Locale.ROOT);
    }

    record Place(String label, double latitude, double longitude) {
    }
}
