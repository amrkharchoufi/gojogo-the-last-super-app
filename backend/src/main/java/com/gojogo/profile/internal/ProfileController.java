package com.gojogo.profile.internal;

import com.gojogo.profile.ProfileDto;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

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
}
