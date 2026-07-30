package com.gojogo.media.internal;

import com.gojogo.profile.ProfileApi;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
class MediaController {

    private final PresignService presign;
    private final ProfileApi profiles;

    MediaController(PresignService presign, ProfileApi profiles) {
        this.presign = presign;
        this.profiles = profiles;
    }

    /**
     * Returns a presigned S3 PUT URL; the client uploads directly to S3
     * (never proxied through the API) and then references publicUrl in
     * posts/stories/avatar.
     */
    @PostMapping("/v1/media/presign")
    PresignResponse presign(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody PresignRequest request) {
        var profile = profiles.createOrFetch(jwt.getSubject(), jwt.getClaimAsString("email"));
        // Uploading as a business only decides which profile folder the object
        // lands in — but it is still an ownership claim, so it is verified.
        UUID owner = profiles.requireActingProfile(profile.id(), request.actAsProfileId());
        return presign.presign(owner, request.contentType());
    }
}

record PresignRequest(@NotBlank String contentType, UUID actAsProfileId) {
}
