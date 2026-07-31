package com.gojogo.profile.internal;

import com.gojogo.profile.ProfileDto;
import com.gojogo.storefront.StorefrontDocument;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * The owner's side of a business profile. Reading one is not here on purpose:
 * a business is a profile, so the public read is the ordinary profile view
 * (which now carries the business block).
 */
@RestController
class BusinessProfileController {

    private final BusinessProfileService businesses;
    private final ProfileService profiles;

    BusinessProfileController(BusinessProfileService businesses, ProfileService profiles) {
        this.businesses = businesses;
        this.profiles = profiles;
    }

    @PostMapping("/v1/profiles/businesses")
    @ResponseStatus(HttpStatus.CREATED)
    BusinessProfileResponse create(@AuthenticationPrincipal Jwt jwt,
                                   @Valid @RequestBody CreateBusinessRequest request) {
        return businesses.create(me(jwt).id(), request);
    }

    @GetMapping("/v1/profiles/businesses/mine")
    List<BusinessProfileResponse> mine(@AuthenticationPrincipal Jwt jwt) {
        return businesses.mine(me(jwt).id());
    }

    @GetMapping("/v1/profiles/businesses/{businessProfileId}")
    BusinessProfileResponse get(@AuthenticationPrincipal Jwt jwt,
                                @PathVariable UUID businessProfileId) {
        return businesses.get(me(jwt).id(), businessProfileId);
    }

    @PatchMapping("/v1/profiles/businesses/{businessProfileId}")
    BusinessProfileResponse update(@AuthenticationPrincipal Jwt jwt,
                                   @PathVariable UUID businessProfileId,
                                   @Valid @RequestBody UpdateBusinessRequest request) {
        return businesses.update(me(jwt).id(), businessProfileId, request);
    }

    /**
     * The business's home page — the same block document a merchant storefront
     * is (SPECS §9), on the surface that takes no catalog blocks.
     *
     * <p>Owner-scoped, and not called by iOS: this is GoJoAdmin's Studio
     * contract. The public read rides on the profile view.
     */
    @GetMapping("/v1/profiles/businesses/{businessProfileId}/home")
    StorefrontDocument home(@AuthenticationPrincipal Jwt jwt,
                            @PathVariable UUID businessProfileId) {
        return businesses.home(me(jwt).id(), businessProfileId);
    }

    @PutMapping("/v1/profiles/businesses/{businessProfileId}/home")
    StorefrontDocument saveHome(@AuthenticationPrincipal Jwt jwt,
                                @PathVariable UUID businessProfileId,
                                @Valid @RequestBody SaveHomeRequest request) {
        return businesses.saveHome(me(jwt).id(), businessProfileId, request.blocks());
    }

    private ProfileDto me(Jwt jwt) {
        return profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email"));
    }
}
