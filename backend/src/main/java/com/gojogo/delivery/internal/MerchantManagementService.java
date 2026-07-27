package com.gojogo.delivery.internal;

import com.gojogo.delivery.MerchantProvisioningApi;
import com.gojogo.delivery.MerchantRegistration;
import com.gojogo.media.MediaApi;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * The restaurant owner's side of the catalog: their merchant row and its menu.
 *
 * <p>Separate from {@link DeliveryService}, which is the customer's side — they
 * share a schema but nothing else, and folding "edit my prices" into the class
 * that also prices orders is how a bug becomes a mispriced receipt.
 *
 * <p>Authorisation is one rule, applied in one place: the caller must be the
 * merchant's {@code ownerId}. Delivery knows nothing about applications, KYC or
 * approval — {@code partner} decided all of that when it called
 * {@link MerchantProvisioningApi#provisionMerchant}, and the ownership stamp is
 * all that survives into this module.
 *
 * <p>What is deliberately <em>not</em> here: incoming orders. A merchant cannot
 * accept, reject or advance an order, because {@code OrderFulfilmentJob} walks
 * every order along a simulated timeline — giving the kitchen a button that the
 * job would immediately overrule is worse than not having one. That surface
 * arrives with the Phase 3 {@code dispatch} module, which replaces the job.
 */
@Service
class MerchantManagementService implements MerchantProvisioningApi {

    private final MerchantRepository merchants;
    private final MenuSectionRepository sections;
    private final MenuItemRepository items;
    private final MediaApi media;

    MerchantManagementService(MerchantRepository merchants, MenuSectionRepository sections,
                              MenuItemRepository items, MediaApi media) {
        this.merchants = merchants;
        this.sections = sections;
        this.items = items;
        this.media = media;
    }

    // MARK: Provisioning (called by the partner module through the public API)

    @Override
    @Transactional
    public UUID provisionMerchant(MerchantRegistration registration) {
        // Idempotent: a retried approval must not hand one partner two
        // restaurants, and there is no second thing an owner could want.
        return merchants.findFirstByOwnerId(registration.ownerId())
            .map(Merchant::getId)
            .orElseGet(() -> {
                Merchant merchant = merchants.save(new Merchant(
                    registration.ownerId(), registration.name(), registration.cuisine(),
                    registration.imageUrl(), registration.latitude(), registration.longitude()));
                media.markReferenced(Collections.singletonList(registration.imageUrl()));
                return merchant.getId();
            });
    }

    @Override
    @Transactional
    public void setMerchantSuspended(UUID merchantId, boolean suspended) {
        merchants.findById(merchantId).ifPresent(m -> m.setSuspended(suspended));
    }

    // MARK: The owner's restaurant

    /**
     * The caller's restaurant, menu included — unavailable dishes and all,
     * unlike the customer-facing detail, because a sold-out dish is exactly
     * what its owner needs to see in order to put it back.
     */
    @Transactional(readOnly = true)
    MyMerchantDto mine(UUID me) {
        return toDto(require(me));
    }

    @Transactional
    MyMerchantDto update(UUID me, UpdateMerchantRequest request) {
        Merchant merchant = require(me);
        merchant.apply(request.name(), request.cuisine(), request.imageUrl(), request.promo(),
            Math.clamp(request.etaMinutes(), 5, 180),
            Math.max(0, request.deliveryFeeCents()),
            request.latitude(), request.longitude(),
            cleaned(request.categories()), cleaned(request.tags()));
        media.markReferenced(Collections.singletonList(request.imageUrl()));
        return toDto(merchant);
    }

    /**
     * Opens or closes the restaurant. Opening one with nothing orderable on it
     * is refused: a customer who taps through to an empty menu has been sent to
     * a dead end by the catalog itself.
     */
    @Transactional
    MyMerchantDto setOpen(UUID me, boolean open) {
        Merchant merchant = require(me);
        if (open) {
            if (merchant.isSuspended()) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Your restaurant is suspended — get in touch to reopen it");
            }
            if (items.countAvailableForMerchant(merchant.getId()) == 0) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Add at least one available dish before you open");
            }
        }
        merchant.setActive(open);
        return toDto(merchant);
    }

    // MARK: Menu

    @Transactional
    MyMerchantDto addSection(UUID me, MenuSectionRequest request) {
        Merchant merchant = require(me);
        sections.save(new MenuSection(merchant.getId(), request.name(),
            sections.maxSortOrder(merchant.getId()) + 1));
        return toDto(merchant);
    }

    @Transactional
    MyMerchantDto renameSection(UUID me, UUID sectionId, MenuSectionRequest request) {
        Merchant merchant = require(me);
        requireSection(merchant, sectionId).rename(request.name());
        return toDto(merchant);
    }

    /** Deleting a section takes its dishes with it (the FK cascades). Past
     *  orders are untouched: an order line copied the dish's name and price at
     *  order time and holds no reference back to the menu. */
    @Transactional
    MyMerchantDto deleteSection(UUID me, UUID sectionId) {
        Merchant merchant = require(me);
        sections.delete(requireSection(merchant, sectionId));
        sections.flush();
        return closeIfNothingLeft(merchant);
    }

    @Transactional
    MyMerchantDto addItem(UUID me, UUID sectionId, MenuItemRequest request) {
        Merchant merchant = require(me);
        requireSection(merchant, sectionId);
        MenuItem item = new MenuItem(sectionId, items.maxSortOrder(sectionId) + 1);
        item.apply(request.name(), request.detail(), request.priceCents(), request.imageUrl(),
            request.popular(), request.available());
        items.save(item);
        media.markReferenced(Collections.singletonList(request.imageUrl()));
        return toDto(merchant);
    }

    @Transactional
    MyMerchantDto updateItem(UUID me, UUID itemId, MenuItemRequest request) {
        Merchant merchant = require(me);
        MenuItem item = requireItem(merchant, itemId);
        item.apply(request.name(), request.detail(), request.priceCents(), request.imageUrl(),
            request.popular(), request.available());
        if (request.sectionId() != null && !request.sectionId().equals(item.getSectionId())) {
            requireSection(merchant, request.sectionId());
            item.moveTo(request.sectionId(), items.maxSortOrder(request.sectionId()) + 1);
        }
        media.markReferenced(Collections.singletonList(request.imageUrl()));
        items.flush();
        return closeIfNothingLeft(merchant);
    }

    @Transactional
    MyMerchantDto deleteItem(UUID me, UUID itemId) {
        Merchant merchant = require(me);
        items.delete(requireItem(merchant, itemId));
        items.flush();
        return closeIfNothingLeft(merchant);
    }

    /**
     * An open restaurant whose last orderable dish just went closes itself.
     * The alternative is a live catalog entry that 400s every order — the owner
     * gets told, and reopens with one tap once the menu is back.
     */
    private MyMerchantDto closeIfNothingLeft(Merchant merchant) {
        if (merchant.isActive() && items.countAvailableForMerchant(merchant.getId()) == 0) {
            merchant.setActive(false);
        }
        return toDto(merchant);
    }

    // MARK: Lookups

    /** 404, not 403: a caller with no restaurant and a caller who is not this
     *  restaurant's owner are the same answer — you have no restaurant here. */
    private Merchant require(UUID me) {
        return merchants.findFirstByOwnerId(me).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "You don't manage a restaurant"));
    }

    private MenuSection requireSection(Merchant merchant, UUID sectionId) {
        return sections.findById(sectionId)
            .filter(s -> s.getMerchantId().equals(merchant.getId()))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such menu section"));
    }

    private MenuItem requireItem(Merchant merchant, UUID itemId) {
        MenuItem item = items.findById(itemId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such dish"));
        requireSection(merchant, item.getSectionId());
        return item;
    }

    private static Set<String> cleaned(List<String> values) {
        Set<String> out = new LinkedHashSet<>();
        if (values != null) {
            for (String value : values) {
                if (value != null && !value.isBlank()) {
                    out.add(value.trim());
                }
            }
        }
        return out;
    }

    // MARK: Mapping

    /** One query per section, like the customer-facing catalog mapping — a
     *  single restaurant's menu, and the alternative paginates in memory. */
    private MyMerchantDto toDto(Merchant merchant) {
        List<MyMenuSectionDto> menu = sections.findByMerchantIdOrderBySortOrderAsc(merchant.getId())
            .stream()
            .map(section -> new MyMenuSectionDto(section.getId(), section.getName(),
                items.findBySectionIdOrderBySortOrderAsc(section.getId()).stream()
                    .map(item -> new MyMenuItemDto(item.getId(), item.getName(), item.getDetail(),
                        item.getPriceCents(), item.getImageUrl(), item.isPopular(),
                        item.isAvailable()))
                    .toList()))
            .toList();
        return new MyMerchantDto(
            merchant.getId(), merchant.getName(), merchant.getCuisine(), merchant.getImageUrl(),
            merchant.getPromo(), merchant.getEtaMinutes(), merchant.getDeliveryFeeCents(),
            merchant.getRating().doubleValue(), merchant.getReviewCount(),
            merchant.getLatitude(), merchant.getLongitude(),
            List.copyOf(merchant.getCategories()), List.copyOf(merchant.getTags()),
            merchant.isActive(), merchant.isSuspended(), menu);
    }
}
