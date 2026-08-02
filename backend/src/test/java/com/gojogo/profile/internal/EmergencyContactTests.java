package com.gojogo.profile.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.profile.EmergencyContactDto;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.web.server.ResponseStatusException;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * The list an SOS reaches (SPECS §10).
 *
 * <p>Small, and the interesting part is what it does <em>not</em> require: a
 * contact is a phone number, and a GojoGo account is optional. The person you
 * would call in an emergency is usually not a user of the app you happen to be
 * sitting in, and a list that only held accounts would be empty at the moment it
 * mattered.
 */
class EmergencyContactTests {

    private static final UUID ME = UUID.randomUUID();

    private final List<EmergencyContact> stored = new ArrayList<>();
    private EmergencyContactRepository contacts;
    private EmergencyContactService service;

    @BeforeEach
    void setUp() {
        contacts = mock(EmergencyContactRepository.class);
        UserProfileRepository profiles = mock(UserProfileRepository.class);
        ConfigApi config = mock(ConfigApi.class);
        when(config.number(anyString(), anyLong()))
            .thenAnswer(call -> call.getArgument(1, Long.class));
        when(profiles.findById(any())).thenReturn(Optional.empty());
        when(contacts.findByProfileIdOrderBySortOrderAscCreatedAtAsc(any()))
            .thenAnswer(call -> stored.stream()
                .filter(c -> c.getProfileId().equals(call.getArgument(0)))
                .toList());
        when(contacts.save(any())).thenAnswer(call -> {
            EmergencyContact saved = call.getArgument(0);
            set(saved, "id", UUID.randomUUID());
            stored.add(saved);
            return saved;
        });
        when(contacts.findById(any())).thenAnswer(call -> stored.stream()
            .filter(c -> call.getArgument(0).equals(c.getId()))
            .findFirst());
        service = new EmergencyContactService(contacts, profiles, config);
    }

    @Test
    @DisplayName("a contact needs a number and nothing else")
    void addsAContactWithJustANumber() {
        EmergencyContactDto added = add("Mum", "+212600000000", null);

        assertThat(added.name()).isEqualTo("Mum");
        assertThat(added.phone()).isEqualTo("+212600000000");
        assertThat(added.linkedProfileId()).isNull();
        assertThat(service.forProfile(ME)).hasSize(1);
    }

    @Test
    @DisplayName("the fifth is the last — a sixth is refused by name")
    void capsAtFive() {
        for (int i = 0; i < 5; i++) {
            add("Contact " + i, "+21260000000" + i, null);
        }

        assertThatThrownBy(() -> add("One more", "+212611111111", null))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("5 emergency contacts");
    }

    @Test
    @DisplayName("a link to somebody who isn't here is dropped, not refused")
    void unknownLinkIsDroppedRatherThanFatal() {
        EmergencyContactDto added = add("Sara", "+212600000009", UUID.randomUUID());

        // Losing the number too, over a stale profile id, would be the worse
        // failure: the contact is perfectly usable by phone.
        assertThat(added.linkedProfileId()).isNull();
        assertThat(added.phone()).isEqualTo("+212600000009");
    }

    @Test
    @DisplayName("the same number twice is a conflict, not a silent overwrite")
    void duplicateNumberIsAConflict() {
        add("Mum", "+212600000000", null);
        doThrow(new DataIntegrityViolationException("emergency_contact_phone_uk"))
            .when(contacts).flush();

        assertThatThrownBy(() -> add("Mother", "+212600000000", null))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("already one of your emergency contacts");
    }

    @Test
    @DisplayName("somebody else's contact is a 404, not a 403")
    void anotherPersonsContactIsInvisible() {
        UUID id = add("Mum", "+212600000000", null).id();

        assertThatThrownBy(() -> service.remove(UUID.randomUUID(), id))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("404");
    }

    // MARK: Fixtures

    private EmergencyContactDto add(String name, String phone, UUID linked) {
        return service.add(ME, new SaveEmergencyContactRequest(name, phone, "Family", linked));
    }

    private static void set(Object target, String field, Object value) {
        try {
            Field f = target.getClass().getDeclaredField(field);
            f.setAccessible(true);
            f.set(target, value);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }
}
