package com.gojogo.assistant.internal;

import com.gojogo.delivery.DeliveryCatalogApi;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * There is no geocoder on this platform, and a ride is priced between two
 * points. So the interesting behaviour here is the refusal.
 */
class AssistantPlaceResolverTests {

    private static final UUID ME = UUID.randomUUID();

    private final DeliveryCatalogApi delivery = mock(DeliveryCatalogApi.class);
    private final AssistantPlaceResolver resolver = new AssistantPlaceResolver(delivery);

    @Test
    @DisplayName("'home' resolves to the default saved address")
    void homeResolvesToTheDefault() {
        saved(address("Work", "8 Boulevard Zerktouni", 33.58, -7.63, false),
            address("Home", "12 Rue des Orangers", 33.59, -7.61, true));

        assertThat(resolver.resolve(ME, "home")).get()
            .extracting(AssistantPlaceResolver.Place::label).isEqualTo("Home");
    }

    @Test
    @DisplayName("the launch languages' words for home resolve too")
    void frenchAndSpanishResolve() {
        saved(address("Chez moi", "12 Rue des Orangers", 33.59, -7.61, true));

        assertThat(resolver.resolve(ME, "chez moi")).isPresent();
        assertThat(resolver.resolve(ME, "mi casa")).isPresent();
    }

    @Test
    @DisplayName("a place matches on its label or its street line")
    void labelsAndStreetsBothMatch() {
        saved(address("Work", "8 Boulevard Zerktouni", 33.58, -7.63, true));

        assertThat(resolver.resolve(ME, "work")).isPresent();
        assertThat(resolver.resolve(ME, "Boulevard Zerktouni")).isPresent();
    }

    @Test
    @DisplayName("an unknown place resolves to nothing rather than to somewhere")
    void unknownPlaceIsRefused() {
        saved(address("Home", "12 Rue des Orangers", 33.59, -7.61, true));

        // The failure mode this prevents: a fare quoted for a trip the user is
        // not taking, which they then act on. Nothing about the answer would
        // look wrong.
        assertThat(resolver.resolve(ME, "Casablanca airport")).isEmpty();
        assertThat(resolver.knownPlaces(ME)).containsExactly("Home");
    }

    @Test
    @DisplayName("a saved address with no map pin cannot price a ride")
    void addressWithoutCoordinatesIsNotAPlace() {
        saved(address("Home", "12 Rue des Orangers", null, null, true));

        assertThat(resolver.resolve(ME, "home"))
            .as("the app allows a typed line with no pin; travel cannot route from one")
            .isEmpty();
    }

    private void saved(DeliveryCatalogApi.SavedAddress... addresses) {
        when(delivery.addressesOf(any())).thenReturn(List.of(addresses));
    }

    private static DeliveryCatalogApi.SavedAddress address(String label, String line1,
                                                           Double lat, Double lon,
                                                           boolean isDefault) {
        return new DeliveryCatalogApi.SavedAddress(UUID.randomUUID(), label, line1, lat, lon,
            isDefault);
    }
}
