package com.gojogo.profile.internal;

import com.gojogo.profile.ProfileDto;
import com.gojogo.profile.ProfileKind;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
class ProfileController {

    private final ProfileService profiles;

    ProfileController(ProfileService profiles) {
        this.profiles = profiles;
    }

    @GetMapping("/v1/profiles/me")
    ProfileDto me(@AuthenticationPrincipal Jwt jwt) {
        return profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email"));
    }

    @PatchMapping("/v1/profiles/me")
    ProfileDto updateMe(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody UpdateProfileRequest request) {
        return profiles.updateOwn(jwt.getSubject(), jwt.getClaimAsString("email"), request);
    }

    /** Change username (2-month cooldown, enforced server-side). 429 if too soon, 409 if taken. */
    @PutMapping("/v1/profiles/me/handle")
    ProfileDto changeHandle(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody ChangeHandleRequest request) {
        return profiles.changeHandle(jwt.getSubject(), jwt.getClaimAsString("email"), request.handle());
    }

    /** Cooldown state for the caller's handle so the UI can gate the change control. */
    @GetMapping("/v1/profiles/me/handle-status")
    HandleStatusResponse handleStatus(@AuthenticationPrincipal Jwt jwt) {
        return profiles.handleStatus(jwt.getSubject(), jwt.getClaimAsString("email"));
    }

    /** Live availability check for a candidate username (format + not taken by another user). */
    @GetMapping("/v1/profiles/me/handle-available")
    HandleAvailabilityResponse handleAvailable(@AuthenticationPrincipal Jwt jwt,
                                               @RequestParam("handle") String handle) {
        return profiles.handleAvailability(jwt.getSubject(), handle);
    }

    /**
     * People picker — what the @-tag autocomplete calls on each keystroke.
     * A blank {@code q} returns an empty list rather than the user table.
     *
     * <p>Sits above {@code /v1/profiles/{profileId}} (social's) only because a
     * literal path segment outranks a variable one; the name is reserved for
     * this and must not become somebody's username.
     */
    @GetMapping("/v1/profiles/search")
    List<ProfileSearchResult> search(@RequestParam(name = "q", required = false) String query,
                                     @RequestParam(defaultValue = "10") int limit) {
        return profiles.search(query, limit).stream()
            .map(p -> new ProfileSearchResult(p.id(),
                p.displayName() != null ? p.displayName() : p.handle(),
                p.handle(), p.avatarUrl(),
                p.kind() == ProfileKind.BUSINESS, p.verified()))
            .toList();
    }
}
