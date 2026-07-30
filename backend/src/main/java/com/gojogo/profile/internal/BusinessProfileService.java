package com.gojogo.profile.internal;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.UUID;

/**
 * Creating and running a business profile. Everything social about it — posts,
 * followers, stories — is the plain profile machinery; this class only owns the
 * business half and the ownership rule that guards it.
 */
@Service
class BusinessProfileService {

    /**
     * SPECS.md §8 CONFIG {@code maxBusinessesPerOwner}. A constant until the
     * platform config registry lands (Phase 2e M3) — one place to move it from.
     */
    private static final int MAX_BUSINESSES_PER_OWNER = 5;

    private final UserProfileRepository profiles;
    private final BusinessProfileRepository businesses;
    private final ProfileService profileService;

    BusinessProfileService(UserProfileRepository profiles, BusinessProfileRepository businesses,
                           ProfileService profileService) {
        this.profiles = profiles;
        this.businesses = businesses;
        this.profileService = profileService;
    }

    @Transactional
    BusinessProfileResponse create(UUID ownerProfileId, CreateBusinessRequest request) {
        if (businesses.countByOwnerProfileId(ownerProfileId) >= MAX_BUSINESSES_PER_OWNER) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "You can run at most " + MAX_BUSINESSES_PER_OWNER + " business profiles.");
        }
        String handle = request.handle() == null || request.handle().isBlank()
            ? profileService.uniqueHandle(request.displayName())
            : requestedHandle(request.handle());

        UserProfile profile = profiles.saveAndFlush(
            UserProfile.business(handle, request.displayName().trim()));
        if (request.bio() != null) {
            profile.setBio(request.bio());
        }
        // "Creator" is the default every profile is born with; a business that
        // didn't say what it does is a business, not a creator.
        profile.setCategory(request.category() == null || request.category().isBlank()
            ? "Business" : request.category().trim());
        if (request.avatarUrl() != null && !request.avatarUrl().isBlank()) {
            profile.setAvatarUrl(request.avatarUrl());
        }

        BusinessProfile business = new BusinessProfile(profile.getId(), ownerProfileId);
        business.setContactPhone(request.contactPhone());
        business.setContactEmail(request.contactEmail());
        business.setWebsiteUrl(request.websiteUrl());
        business.setAddressLine(request.addressLine());
        business.setCity(request.city());
        business.setCountry(request.country());
        business.setLatitude(request.latitude());
        business.setLongitude(request.longitude());
        business.setOpeningHours(request.openingHours());
        return toResponse(profiles.save(profile), businesses.save(business));
    }

    @Transactional(readOnly = true)
    List<BusinessProfileResponse> mine(UUID ownerProfileId) {
        return businesses.findByOwnerProfileIdOrderByCreatedAtDesc(ownerProfileId).stream()
            .flatMap(b -> profiles.findById(b.getProfileId()).map(p -> toResponse(p, b)).stream())
            .toList();
    }

    @Transactional(readOnly = true)
    BusinessProfileResponse get(UUID ownerProfileId, UUID businessProfileId) {
        BusinessProfile business = requireOwned(ownerProfileId, businessProfileId);
        return toResponse(requireProfile(businessProfileId), business);
    }

    @Transactional
    BusinessProfileResponse update(UUID ownerProfileId, UUID businessProfileId,
                                   UpdateBusinessRequest request) {
        BusinessProfile business = requireOwned(ownerProfileId, businessProfileId);
        UserProfile profile = requireProfile(businessProfileId);

        if (request.displayName() != null && !request.displayName().isBlank()) {
            profile.setDisplayName(request.displayName().trim());
        }
        if (request.handle() != null && !request.handle().isBlank()) {
            String handle = requestedHandle(request.handle());
            if (!handle.equals(profile.getHandle())) {
                // No cooldown here — the two-month rule protects a person's
                // identity from being churned, and a business owner renaming
                // their own shop is not that.
                profile.setHandle(handle);
            }
        }
        if (request.bio() != null) {
            profile.setBio(request.bio());
        }
        if (request.category() != null) {
            profile.setCategory(request.category().isBlank() ? "Business" : request.category().trim());
        }
        if (request.avatarUrl() != null) {
            profile.setAvatarUrl(request.avatarUrl().isBlank() ? null : request.avatarUrl());
        }
        if (request.contactPhone() != null) {
            business.setContactPhone(request.contactPhone());
        }
        if (request.contactEmail() != null) {
            business.setContactEmail(request.contactEmail());
        }
        if (request.websiteUrl() != null) {
            business.setWebsiteUrl(request.websiteUrl());
        }
        if (request.addressLine() != null) {
            business.setAddressLine(request.addressLine());
        }
        if (request.city() != null) {
            business.setCity(request.city());
        }
        if (request.country() != null) {
            business.setCountry(request.country());
        }
        if (request.latitude() != null) {
            business.setLatitude(request.latitude());
        }
        if (request.longitude() != null) {
            business.setLongitude(request.longitude());
        }
        if (request.openingHours() != null) {
            business.setOpeningHours(request.openingHours());
        }
        return toResponse(profiles.save(profile), businesses.save(business));
    }

    private BusinessProfile requireOwned(UUID ownerProfileId, UUID businessProfileId) {
        BusinessProfile business = businesses.findById(businessProfileId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such business profile"));
        if (!business.getOwnerProfileId().equals(ownerProfileId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "That business isn't yours.");
        }
        return business;
    }

    private UserProfile requireProfile(UUID profileId) {
        return profiles.findById(profileId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such business profile"));
    }

    /** A handle the owner asked for: valid, and not already someone's. */
    private String requestedHandle(String raw) {
        String handle = Handles.normalize(raw);
        if (handle.length() < Handles.MIN_LENGTH) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Username must be at least " + Handles.MIN_LENGTH
                    + " characters (letters, numbers, _ or .).");
        }
        if (profiles.existsByHandle(handle)) {
            throw new HandleTakenException(handle);
        }
        return handle;
    }

    private static BusinessProfileResponse toResponse(UserProfile p, BusinessProfile b) {
        return new BusinessProfileResponse(p.getId(), p.getHandle(), p.getDisplayName(), p.getBio(),
            p.getCategory(), p.getAvatarUrl(), b.getOwnerProfileId(), b.isVerified(),
            b.getContactPhone(), b.getContactEmail(), b.getWebsiteUrl(),
            b.getAddressLine(), b.getCity(), b.getCountry(),
            b.getLatitude(), b.getLongitude(), b.getOpeningHours());
    }
}
