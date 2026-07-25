package com.gojogo.economy.internal;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/**
 * Dev-only marketplace cleanup: list what's in {@code economy.listing}, then
 * delete some or all of it. For clearing test listings out of an environment —
 * sellers manage their own listings through {@link EconomyController}, which is
 * the only path the app ever uses.
 *
 * <p>Off unless switched on. The endpoints answer 404 — not 401 or 403 — unless
 * the caller presents {@value #TOKEN_HEADER} matching {@code ECONOMY_ADMIN_TOKEN},
 * which production leaves unset, so there is nothing here to find. They are
 * exempt from the JWT filter chain on purpose (SecurityConfig): the point is to
 * be usable from one curl without minting a user token.
 *
 * <pre>
 * # what's out there
 * curl -H "X-Economy-Admin-Token: $TOKEN" https://api.gojogo.app/v1/economy/admin/listings
 *
 * # everything
 * curl -X POST -H "X-Economy-Admin-Token: $TOKEN" -H 'Content-Type: application/json' \
 *   -d '{"confirm":"PURGE"}' https://api.gojogo.app/v1/economy/admin/listings/purge
 *
 * # one listing
 * curl -X POST -H "X-Economy-Admin-Token: $TOKEN" -H 'Content-Type: application/json' \
 *   -d '{"confirm":"PURGE","listingIds":["..."]}' https://api.gojogo.app/v1/economy/admin/listings/purge
 * </pre>
 *
 * Deletion is permanent and takes the listing's photos and saves with it.
 */
@RestController
@EnableConfigurationProperties(EconomyAdminProperties.class)
class EconomyAdminController {

    static final String TOKEN_HEADER = "X-Economy-Admin-Token";

    private static final Logger log = LoggerFactory.getLogger(EconomyAdminController.class);

    private final ListingAdminService admin;
    private final EconomyAdminProperties props;

    EconomyAdminController(ListingAdminService admin, EconomyAdminProperties props) {
        this.admin = admin;
        this.props = props;
        if (props.enabled()) {
            log.warn("Economy cleanup endpoints are ENABLED at /v1/economy/admin/** — "
                + "unset ECONOMY_ADMIN_TOKEN and redeploy once the wipe is done");
        } else if (props.tooShort()) {
            log.warn("ECONOMY_ADMIN_TOKEN is shorter than {} characters, so the economy "
                + "cleanup endpoints stay disabled", EconomyAdminProperties.MIN_TOKEN_LENGTH);
        }
    }

    @GetMapping("/v1/economy/admin/listings")
    List<AdminListingSummary> inventory(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @RequestParam(defaultValue = "200") int limit) {
        authorize(token);
        return admin.inventory(limit);
    }

    @PostMapping("/v1/economy/admin/listings/purge")
    PurgeListingsResponse purge(
            @RequestHeader(name = TOKEN_HEADER, required = false) String token,
            @Valid @RequestBody PurgeListingsRequest request) {
        authorize(token);
        PurgeListingsResponse result = admin.purge(request);
        log.warn("Economy cleanup deleted {} listing(s); {} remain", result.deleted(), result.remaining());
        return result;
    }

    /** 404 rather than 403: with no token configured — or a wrong one presented —
     *  these paths shouldn't admit that they exist. */
    private void authorize(String presented) {
        if (!props.matches(presented)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such endpoint");
        }
    }
}

/** One row of the cleanup inventory — enough to recognise a listing before
 *  deleting it, without the seller-profile and saved-state joins browse does. */
record AdminListingSummary(UUID id, UUID sellerId, String title, String status,
                           int photoCount, OffsetDateTime createdAt) {
}

/**
 * What to delete. {@code listingIds} picks specific listings, {@code sellerId}
 * takes one seller's shelf, and neither means the whole marketplace —
 * {@code confirm} has to spell PURGE either way.
 */
record PurgeListingsRequest(@NotBlank String confirm, UUID sellerId, List<UUID> listingIds) {
}

record PurgeListingsResponse(int deleted, long remaining) {
}
