package com.gojogo.profile.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.profile.EmergencyContactDto;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.UUID;

/**
 * The list SOS reads (SPECS §10).
 *
 * <p>Small on purpose. The only rules are a cap — five, config — and that the
 * same number cannot be in the list twice, which is a mistake rather than a
 * preference and is held by a unique index rather than by a check here.
 *
 * <p><strong>Storing a number does not make us able to text it.</strong> Real
 * SMS is still an open item (PROGRESS "Needs YOU" #3), so an unlinked contact is
 * reached by the phone's own message composer, which the app opens with the
 * text already written. That is not a workaround: a message that arrives from
 * the person in trouble, on their own number, is the one their mother will
 * actually open.
 */
@Service
class EmergencyContactService {

    private final EmergencyContactRepository contacts;
    private final UserProfileRepository profiles;
    private final ConfigApi config;

    EmergencyContactService(EmergencyContactRepository contacts, UserProfileRepository profiles,
                            ConfigApi config) {
        this.contacts = contacts;
        this.profiles = profiles;
        this.config = config;
    }

    @Transactional(readOnly = true)
    List<EmergencyContactDto> forProfile(UUID profileId) {
        return contacts.findByProfileIdOrderBySortOrderAscCreatedAtAsc(profileId).stream()
            .map(EmergencyContactService::toDto)
            .toList();
    }

    int max() {
        return (int) Math.clamp(config.number("profile.emergency.contacts.max", 5), 1, 20);
    }

    @Transactional
    EmergencyContactDto add(UUID profileId, SaveEmergencyContactRequest request) {
        List<EmergencyContact> existing =
            contacts.findByProfileIdOrderBySortOrderAscCreatedAtAsc(profileId);
        if (existing.size() >= max()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "You can keep " + max() + " emergency contacts — remove one first");
        }
        EmergencyContact contact = new EmergencyContact(profileId, existing.size());
        contact.apply(request.name(), request.phone(), request.relationship(),
            resolveLink(request.linkedProfileId()));
        return save(contacts.save(contact));
    }

    @Transactional
    EmergencyContactDto update(UUID profileId, UUID contactId,
                               SaveEmergencyContactRequest request) {
        EmergencyContact contact = require(profileId, contactId);
        contact.apply(request.name(), request.phone(), request.relationship(),
            resolveLink(request.linkedProfileId()));
        return save(contact);
    }

    @Transactional
    void remove(UUID profileId, UUID contactId) {
        contacts.delete(require(profileId, contactId));
    }

    private EmergencyContactDto save(EmergencyContact contact) {
        try {
            contacts.flush();
        } catch (DataIntegrityViolationException duplicate) {
            // The unique index caught the same number twice. A conflict rather
            // than a silent merge: two rows for one person is a mistake, and
            // quietly overwriting the other one would lose a name.
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That number is already one of your emergency contacts");
        }
        return toDto(contact);
    }

    /** 404 rather than 403 for somebody else's contact — don't confirm it
     *  exists. */
    private EmergencyContact require(UUID profileId, UUID contactId) {
        return contacts.findById(contactId)
            .filter(c -> c.getProfileId().equals(profileId))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such contact"));
    }

    /** A link to somebody who isn't here is dropped rather than refused: the
     *  contact is still perfectly usable by phone, and failing the whole save
     *  over a stale profile id would lose the number too. */
    private UUID resolveLink(UUID claimed) {
        if (claimed == null) return null;
        return profiles.findById(claimed).map(UserProfile::getId).orElse(null);
    }

    private static EmergencyContactDto toDto(EmergencyContact contact) {
        return new EmergencyContactDto(contact.getId(), contact.getName(), contact.getPhone(),
            contact.getRelationship(), contact.getLinkedProfileId());
    }
}

interface EmergencyContactRepository extends JpaRepository<EmergencyContact, UUID> {

    List<EmergencyContact> findByProfileIdOrderBySortOrderAscCreatedAtAsc(UUID profileId);

    void deleteByProfileId(UUID profileId);
}
