package com.gojogo.profile.internal;

import com.gojogo.profile.EmergencyContactDto;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * Emergency contacts (Phase 3 M5, SPECS §10) — the list an SOS reaches.
 *
 * <pre>
 * curl -X POST -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
 *   -d '{"name":"Mum","phone":"+212600000000","relationship":"Family"}' \
 *   https://api.gojogo.app/v1/me/emergency-contacts
 * </pre>
 */
@RestController
class EmergencyContactController {

    private final EmergencyContactService contacts;
    private final ProfileService profiles;

    EmergencyContactController(EmergencyContactService contacts, ProfileService profiles) {
        this.contacts = contacts;
        this.profiles = profiles;
    }

    @GetMapping("/v1/me/emergency-contacts")
    EmergencyContactsResponse list(@AuthenticationPrincipal Jwt jwt) {
        return new EmergencyContactsResponse(contacts.forProfile(me(jwt)), contacts.max());
    }

    @PostMapping("/v1/me/emergency-contacts")
    @ResponseStatus(HttpStatus.CREATED)
    EmergencyContactDto add(@AuthenticationPrincipal Jwt jwt,
                            @Valid @RequestBody SaveEmergencyContactRequest body) {
        return contacts.add(me(jwt), body);
    }

    @PutMapping("/v1/me/emergency-contacts/{contactId}")
    EmergencyContactDto update(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID contactId,
                               @Valid @RequestBody SaveEmergencyContactRequest body) {
        return contacts.update(me(jwt), contactId, body);
    }

    @DeleteMapping("/v1/me/emergency-contacts/{contactId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void remove(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID contactId) {
        contacts.remove(me(jwt), contactId);
    }

    private UUID me(Jwt jwt) {
        return profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email")).id();
    }
}

/** @param linkedProfileId optional: the contact is also on GojoGo, so an alarm
 *                         can reach them as a push rather than as a message the
 *                         person in trouble has to send by hand */
record SaveEmergencyContactRequest(@NotBlank @Size(max = 80) String name,
                                   @NotBlank @Size(min = 3, max = 32) String phone,
                                   @Size(max = 40) String relationship,
                                   UUID linkedProfileId) {
}

/** @param max how many are allowed, so the screen can say "3 of 5" rather than
 *             finding out by being refused */
record EmergencyContactsResponse(List<EmergencyContactDto> contacts, int max) {
}
