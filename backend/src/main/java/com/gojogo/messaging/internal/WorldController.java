package com.gojogo.messaging.internal;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * My World setup surface (WhatsApp-style): phone verification + the phone-keyed
 * World profile (its own name/avatar). All Bearer-authed; the caller is the app
 * profile behind the JWT, and the World identity is attached to it.
 */
@RestController
class WorldController {

    private final WorldService world;
    private final CurrentProfile current;

    WorldController(WorldService world, CurrentProfile current) {
        this.world = world;
        this.current = current;
    }

    @GetMapping("/v1/world/me")
    WorldProfileDto me(@AuthenticationPrincipal Jwt jwt) {
        return world.me(current.require(jwt).id());
    }

    @PostMapping("/v1/world/phone/start")
    StartPhoneResponse startPhone(@AuthenticationPrincipal Jwt jwt,
                                  @Valid @RequestBody StartPhoneRequest request) {
        return world.startPhone(current.require(jwt).id(), request.phone());
    }

    @PostMapping("/v1/world/phone/verify")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void verifyPhone(@AuthenticationPrincipal Jwt jwt,
                     @Valid @RequestBody VerifyPhoneRequest request) {
        world.verifyPhone(current.require(jwt).id(), request.phone(), request.code());
    }

    @PutMapping("/v1/world/me")
    WorldProfileDto update(@AuthenticationPrincipal Jwt jwt,
                           @Valid @RequestBody UpdateWorldProfileRequest request) {
        return world.updateProfile(current.require(jwt).id(), request);
    }

    @GetMapping("/v1/world/by-phone/{phone}")
    WorldUserDto byPhone(@AuthenticationPrincipal Jwt jwt, @PathVariable String phone) {
        return world.byPhone(current.require(jwt).id(), phone);
    }
}
