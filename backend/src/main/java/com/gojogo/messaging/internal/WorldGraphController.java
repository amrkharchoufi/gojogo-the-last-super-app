package com.gojogo.messaging.internal;

import jakarta.validation.Valid;
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
 * The GojoMessages graph surface: contacts, circles and the rich profile.
 *
 * <p>Note what isn't here — any way to look somebody up by handle. Contacts are
 * added by phone number and only by phone number, which is the whole shape of
 * this network (ARCHITECTURE Phase 2f).
 */
@RestController
class WorldGraphController {

    private final WorldGraphService graph;
    private final CurrentProfile current;

    WorldGraphController(WorldGraphService graph, CurrentProfile current) {
        this.graph = graph;
        this.current = current;
    }

    // ---- contacts ---------------------------------------------------------

    @GetMapping("/v1/world/contacts")
    List<ContactDto> contacts(@AuthenticationPrincipal Jwt jwt) {
        return graph.listContacts(current.require(jwt).id());
    }

    @PostMapping("/v1/world/contacts")
    ContactDto addContact(@AuthenticationPrincipal Jwt jwt,
                          @Valid @RequestBody AddContactRequest request) {
        return graph.addContact(current.require(jwt).id(), request.phone(), request.alias());
    }

    @DeleteMapping("/v1/world/contacts/{contactId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void removeContact(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID contactId) {
        graph.removeContact(current.require(jwt).id(), contactId);
    }

    // ---- circles ----------------------------------------------------------

    @GetMapping("/v1/world/circles")
    List<CircleDto> circles(@AuthenticationPrincipal Jwt jwt) {
        return graph.listCircles(current.require(jwt).id());
    }

    @PostMapping("/v1/world/circles")
    CircleDto createCircle(@AuthenticationPrincipal Jwt jwt,
                           @Valid @RequestBody SaveCircleRequest request) {
        return graph.createCircle(current.require(jwt).id(), request);
    }

    @PutMapping("/v1/world/circles/{circleId}")
    CircleDto updateCircle(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID circleId,
                           @Valid @RequestBody SaveCircleRequest request) {
        return graph.updateCircle(current.require(jwt).id(), circleId, request);
    }

    @DeleteMapping("/v1/world/circles/{circleId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void deleteCircle(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID circleId) {
        graph.deleteCircle(current.require(jwt).id(), circleId);
    }

    // ---- rich profile -----------------------------------------------------

    @GetMapping("/v1/world/profile")
    WorldRichProfileDto myProfile(@AuthenticationPrincipal Jwt jwt) {
        return graph.myProfile(current.require(jwt).id());
    }

    @PutMapping("/v1/world/profile")
    WorldRichProfileDto updateProfile(@AuthenticationPrincipal Jwt jwt,
                                      @Valid @RequestBody UpdateRichProfileRequest request) {
        return graph.updateProfile(current.require(jwt).id(), request);
    }

    /** Somebody else's identity. The rich half comes back only to a contact. */
    @GetMapping("/v1/world/profile/{contactId}")
    WorldContactProfileDto contactProfile(@AuthenticationPrincipal Jwt jwt,
                                          @PathVariable UUID contactId) {
        return graph.contactProfile(current.require(jwt).id(), contactId);
    }
}
