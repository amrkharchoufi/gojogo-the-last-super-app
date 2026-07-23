package com.gojogo.economy.internal;

import com.gojogo.economy.ListingCreated;
import com.gojogo.media.MediaApi;
import com.gojogo.messaging.MessagingApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
class ListingService {

    private final ListingRepository listings;
    private final SavedListingRepository saves;
    private final ProfileApi profiles;
    private final MediaApi media;
    private final MessagingApi messaging;
    private final ApplicationEventPublisher events;

    ListingService(ListingRepository listings, SavedListingRepository saves,
                   ProfileApi profiles, MediaApi media, MessagingApi messaging,
                   ApplicationEventPublisher events) {
        this.listings = listings;
        this.saves = saves;
        this.profiles = profiles;
        this.media = media;
        this.messaging = messaging;
        this.events = events;
    }

    @Transactional
    ListingResponse create(UUID me, CreateListingRequest request) {
        Listing listing = new Listing(me, request.title().trim(), request.priceCents(),
            request.currency(),
            blankTo(request.category(), "Home"),
            blankTo(request.condition(), "Good"),
            blankTo(request.locationLabel(), "nearby"),
            request.description());
        List<String> images = request.imageUrls() == null ? List.of() : request.imageUrls().stream()
            .filter(u -> u != null && !u.isBlank())
            .toList();
        images.forEach(listing::addMedia);
        Listing saved = listings.save(listing);
        if (!images.isEmpty()) {
            media.markReferenced(images);
        }
        events.publishEvent(new ListingCreated(saved.getId(), me, saved.getTitle(),
            saved.getCategory(), saved.getCreatedAt()));
        return decorate(List.of(saved), me).getFirst();
    }

    @Transactional(readOnly = true)
    ListingPageResponse browse(UUID me, String category, OffsetDateTime before, int limit) {
        OffsetDateTime cursor = before == null ? OffsetDateTime.now().plusMinutes(1) : before;
        int size = Math.clamp(limit, 1, 50);
        List<Listing> page = category == null || category.isBlank() || category.equalsIgnoreCase("All")
            ? listings.browse(cursor, PageRequest.of(0, size))
            : listings.browseByCategory(category, cursor, PageRequest.of(0, size));
        List<ListingResponse> items = decorate(page, me);
        OffsetDateTime nextBefore = page.size() < size ? null : page.getLast().getCreatedAt();
        return new ListingPageResponse(items, nextBefore);
    }

    @Transactional(readOnly = true)
    List<ListingResponse> mine(UUID me, int limit) {
        return decorate(listings.findBySellerIdOrderByCreatedAtDesc(me,
            PageRequest.of(0, Math.clamp(limit, 1, 100))), me);
    }

    @Transactional(readOnly = true)
    List<ListingResponse> saved(UUID me, int limit) {
        List<UUID> ids = saves.savedByUser(me, PageRequest.of(0, Math.clamp(limit, 1, 100)));
        if (ids.isEmpty()) {
            return List.of();
        }
        // Preserve saved-order; findAllById returns unordered, so re-sort.
        Map<UUID, Listing> byId = listings.findAllById(ids).stream()
            .collect(Collectors.toMap(Listing::getId, l -> l));
        List<Listing> ordered = ids.stream().map(byId::get).filter(l -> l != null).toList();
        return decorate(ordered, me);
    }

    @Transactional(readOnly = true)
    ListingResponse get(UUID me, UUID listingId) {
        Listing listing = listings.findById(listingId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such listing"));
        return decorate(List.of(listing), me).getFirst();
    }

    /**
     * Opens (or reuses) the buyer↔seller thread for a listing. Read-only on the
     * economy side: the conversation lives in {@code messaging}, and nothing is
     * posted here — the client prefills {@code suggestedMessage} so the buyer
     * still chooses to send, and a browsed-away listing leaves no empty thread.
     */
    @Transactional(readOnly = true)
    ListingChatResponse openChat(UUID me, UUID listingId) {
        Listing listing = listings.findById(listingId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such listing"));
        UUID seller = listing.getSellerId();
        if (seller.equals(me)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "That's your own listing");
        }
        UUID conversationId = messaging.openDirectConversation(me, seller);
        return new ListingChatResponse(conversationId, seller, opener(listing));
    }

    /** "Hi — is the Leica M6 (12,000 MAD) still available?" */
    private static String opener(Listing listing) {
        String price = listing.getPriceCents() == null
            ? null
            : priceLabel(listing.getPriceCents(), listing.getCurrency());
        return price == null
            ? "Hi — is the " + listing.getTitle() + " still available?"
            : "Hi — is the " + listing.getTitle() + " (" + price + ") still available?";
    }

    private static String priceLabel(long cents, String currency) {
        String code = currency == null || currency.isBlank() ? "USD" : currency;
        long whole = cents / 100;
        long fraction = cents % 100;
        // Grouped: this lands in a message a buyer sends, and "12000 MAD" reads
        // like a typo next to the listing's own formatted price.
        return fraction == 0
            ? String.format(java.util.Locale.ROOT, "%,d %s", whole, code)
            : String.format(java.util.Locale.ROOT, "%,d.%02d %s", whole, fraction, code);
    }

    @Transactional
    void delete(UUID me, UUID listingId) {
        Listing listing = listings.findById(listingId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such listing"));
        if (!listing.getSellerId().equals(me)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your listing");
        }
        listings.delete(listing);
    }

    @Transactional
    void save(UUID me, UUID listingId) {
        if (!listings.existsById(listingId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such listing");
        }
        // Assigned-id entities save via merge (select-then-update), so a duplicate
        // never throws — guard on existence so save_count isn't double-bumped.
        if (saves.existsById(new SavedListing.Key(listingId, me))) {
            return;
        }
        try {
            saves.saveAndFlush(new SavedListing(listingId, me));
            listings.bumpSaveCount(listingId, 1);
        } catch (org.springframework.dao.DataIntegrityViolationException raceLostDuplicate) {
            // a concurrent save won the insert and already counted it — idempotent
        }
    }

    @Transactional
    void unsave(UUID me, UUID listingId) {
        if (saves.deleteByListingIdAndUserId(listingId, me) > 0) {
            listings.bumpSaveCount(listingId, -1);
        }
    }

    List<ListingResponse> decorate(List<Listing> page, UUID me) {
        if (page.isEmpty()) {
            return List.of();
        }
        Set<UUID> listingIds = page.stream().map(Listing::getId).collect(Collectors.toSet());
        Set<UUID> sellerIds = page.stream().map(Listing::getSellerId).collect(Collectors.toSet());
        Map<UUID, ProfileDto> sellers = profiles.findByIds(sellerIds);
        Set<UUID> savedIds = saves.savedListingIds(me, listingIds);
        return page.stream().map(l -> {
            ProfileDto seller = sellers.get(l.getSellerId());
            return new ListingResponse(
                l.getId(),
                toSellerSummary(seller, l.getSellerId()),
                l.getTitle(),
                l.getPriceCents(),
                l.getCurrency(),
                l.getCategory(),
                l.getCondition(),
                l.getLocationLabel(),
                l.getDescription(),
                l.getMedia().stream().map(ListingMedia::getImageUrl).toList(),
                savedIds.contains(l.getId()),
                l.getSellerId().equals(me),
                l.getSaveCount(),
                l.getCreatedAt());
        }).toList();
    }

    private static SellerSummary toSellerSummary(ProfileDto seller, UUID sellerId) {
        if (seller == null) {
            return new SellerSummary(sellerId, "Deleted user", null, null);
        }
        String name = seller.displayName() != null ? seller.displayName() : seller.handle();
        return new SellerSummary(seller.id(), name, seller.handle(), seller.avatarUrl());
    }

    private static String blankTo(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }
}
