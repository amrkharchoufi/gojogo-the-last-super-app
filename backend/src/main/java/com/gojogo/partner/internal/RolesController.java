package com.gojogo.partner.internal;

import com.gojogo.auth.PlatformAdminApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * What this account can be right now — the one call the iOS profile switcher
 * and every "mode" toggle read.
 *
 * <p>Roles are <em>derived</em>, never stored (SPECS.md §8): owning a business
 * profile makes you a business owner, an approved application makes you a
 * merchant, and a dispatch registry row will make you a driver in Phase 3.
 * There is no role table to drift out of sync with the things it describes.
 *
 * <p>It lives in {@code partner} because partner is where the provisioning
 * facts are, and it may depend on {@code profile}; the reverse would be a
 * module cycle.
 */
@RestController
class RolesController {

    private final PartnerAccountRepository accounts;
    private final ProfileApi profiles;
    private final PartnerCurrentProfile current;
    private final PlatformAdminApi admins;

    RolesController(PartnerAccountRepository accounts, ProfileApi profiles,
                    PartnerCurrentProfile current, PlatformAdminApi admins) {
        this.accounts = accounts;
        this.profiles = profiles;
        this.current = current;
        this.admins = admins;
    }

    @GetMapping("/v1/me/roles")
    MyRolesResponse roles(@AuthenticationPrincipal Jwt jwt) {
        UUID me = current.require(jwt).id();
        List<BusinessRole> businesses = profiles.businessesOwnedBy(me).stream()
            .map(RolesController::toBusinessRole)
            .toList();
        List<PartnerRole> partners = accounts.findByUserIdOrderByCreatedAtAsc(me).stream()
            .map(a -> new PartnerRole(a.getKind().name(), a.getStatus().name(),
                a.getProvisionedRefId(), a.getBusinessProfileId()))
            .toList();
        return new MyRolesResponse(me,
            !businesses.isEmpty(),
            businesses,
            partners,
            merchantIds(partners),
            approved(partners, "DRIVER"),
            approved(partners, "COURIER"),
            // Read from the caller's own token, not from a table: platform
            // operators are a Cognito group, so the claim is the fact.
            admins.isPlatformAdmin(jwt));
    }

    private static List<UUID> merchantIds(List<PartnerRole> partners) {
        return partners.stream()
            .filter(p -> "RESTAURANT".equals(p.kind()) && p.refId() != null
                && "APPROVED".equals(p.status()))
            .map(PartnerRole::refId)
            .toList();
    }

    /** Phase 3 will read this from the dispatch registry; until then an approved
     *  application of that kind is the only truth there is (and cannot exist yet). */
    private static boolean approved(List<PartnerRole> partners, String kind) {
        return partners.stream()
            .anyMatch(p -> kind.equals(p.kind()) && "APPROVED".equals(p.status()));
    }

    private static BusinessRole toBusinessRole(ProfileDto p) {
        return new BusinessRole(p.id(), p.handle(),
            p.displayName() != null ? p.displayName() : p.handle(),
            p.avatarUrl(), p.category(), p.verified());
    }
}

record MyRolesResponse(UUID profileId, boolean hasBusiness, List<BusinessRole> businesses,
                       List<PartnerRole> partners, List<UUID> merchantIds,
                       boolean isDriver, boolean isCourier, boolean isPlatformAdmin) {
}

record BusinessRole(UUID profileId, String handle, String displayName, String avatarUrl,
                    String category, boolean verified) {
}

record PartnerRole(String kind, String status, UUID refId, UUID businessProfileId) {
}
