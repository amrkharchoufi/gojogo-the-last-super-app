package com.gojogo.delivery.internal;

import com.gojogo.storefront.StorefrontApi;
import com.gojogo.storefront.StorefrontBlock;
import com.gojogo.storefront.StorefrontDocument;
import com.gojogo.storefront.StorefrontRefKind;
import com.gojogo.storefront.StorefrontSurface;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * The restaurant's own page: the arrangement of blocks a customer sees above
 * the menu (SPECS §9).
 *
 * <p>Delivery owns the <em>authorisation</em> and the <em>references</em>;
 * {@code storefront} owns the document. That split is the point: the platform
 * module can tell a {@code collection} from a {@code hero} but has no idea which
 * dishes are on this menu, and delivery knows exactly that and nothing about
 * block grammar. Neither could do the other's half without learning something it
 * has no business knowing.
 *
 * <p><strong>iOS does not write this.</strong> The write exists for GoJoAdmin's
 * homepage builder (ARCHITECTURE §10b) and answers the owner's own JWT, exactly
 * like the menu editor next to it — no admin-only mirror. Until that console
 * exists the surface is reachable by curl and by nothing else, which is the same
 * posture the config registry and the music catalog ship in.
 */
@Service
class MerchantStorefrontService {

    private final MerchantRepository merchants;
    private final MenuItemRepository items;
    private final MenuSectionRepository sections;
    private final PromotionRepository promotions;
    private final StorefrontApi storefronts;

    MerchantStorefrontService(MerchantRepository merchants, MenuItemRepository items,
                              MenuSectionRepository sections, PromotionRepository promotions,
                              StorefrontApi storefronts) {
        this.merchants = merchants;
        this.items = items;
        this.sections = sections;
        this.promotions = promotions;
        this.storefronts = storefronts;
    }

    /** The public read, for the customer-facing restaurant detail. */
    @Transactional(readOnly = true)
    StorefrontDocument of(UUID merchantId) {
        return storefronts.documentFor(StorefrontSurface.MERCHANT_STOREFRONT, merchantId);
    }

    @Transactional(readOnly = true)
    StorefrontDocument mine(UUID me) {
        return of(require(me).getId());
    }

    @Transactional
    StorefrontDocument save(UUID me, List<StorefrontBlock> blocks) {
        UUID merchantId = require(me).getId();
        return storefronts.save(StorefrontSurface.MERCHANT_STOREFRONT, merchantId, blocks,
            (kind, ids) -> checkOwned(merchantId, kind, ids));
    }

    /**
     * The ownership half of the write.
     *
     * <p>ITEM, SECTION and PROMOTION have to be this restaurant's — a page that
     * featured a competitor's dish would render its name and price out of a
     * catalog nobody here controls, and a promo banner pointing at someone
     * else's discount is a discount this merchant would end up funding.
     *
     * <p>POST and VIDEO are deliberately not checked: delivery has no dependency
     * on {@code social} or {@code watch} and shouldn't grow one to police
     * decoration. An imported post renders through the same public read as
     * everywhere else in the app, so the worst a borrowed id achieves is showing
     * something that was already public.
     */
    private void checkOwned(UUID merchantId, StorefrontRefKind kind, Set<UUID> ids) {
        List<UUID> owned = switch (kind) {
            case ITEM -> items.findForMerchant(merchantId, ids).stream().map(MenuItem::getId).toList();
            case SECTION -> sections.idsForMerchant(merchantId, ids);
            case PROMOTION -> promotions.idsForMerchant(merchantId, ids);
            case POST, VIDEO -> null;
        };
        if (owned == null) {
            return;
        }
        Set<UUID> found = new HashSet<>(owned);
        for (UUID id : ids) {
            if (!found.contains(id)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Your page points at a " + kind.name().toLowerCase()
                        + " that isn't yours: " + id);
            }
        }
    }

    /** Same answer as the menu editor's: a caller with no restaurant and a
     *  caller who isn't this one's owner are told the same thing. */
    private Merchant require(UUID me) {
        return merchants.findFirstByOwnerId(me).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "You don't manage a restaurant"));
    }
}
