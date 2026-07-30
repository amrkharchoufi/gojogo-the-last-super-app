package com.gojogo.profile.internal;

import com.gojogo.profile.BusinessProfileDto;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileAvatarChanged;
import com.gojogo.profile.ProfileDto;
import com.gojogo.profile.ProfileKind;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.time.Period;
import java.util.Collection;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
class ProfileService implements ProfileApi {

    /** Once the free sets are used up, a handle change is allowed at most once per this window. */
    private static final Period HANDLE_CHANGE_COOLDOWN = Period.ofMonths(2);
    /** Free handle sets before the cooldown applies: the onboarding pick + one grace change. */
    private static final int FREE_HANDLE_SETS = 2;
    private static final int HANDLE_MIN_LENGTH = Handles.MIN_LENGTH;

    private final UserProfileRepository repository;
    private final BusinessProfileRepository businesses;
    private final ApplicationEventPublisher events;

    ProfileService(UserProfileRepository repository, BusinessProfileRepository businesses,
                   ApplicationEventPublisher events) {
        this.repository = repository;
        this.businesses = businesses;
        this.events = events;
    }

    @Override
    @Transactional
    public ProfileDto createOrFetch(String cognitoSub, String email) {
        UserProfile profile = repository.findByCognitoSub(cognitoSub)
            .orElseGet(() -> {
                try {
                    return repository.saveAndFlush(new UserProfile(cognitoSub, email, generateHandle(email)));
                } catch (DataIntegrityViolationException raceWithConcurrentFirstLogin) {
                    return repository.findByCognitoSub(cognitoSub).orElseThrow();
                }
            });
        return toDto(profile);
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<ProfileDto> findById(UUID id) {
        return repository.findById(id).map(this::toDto);
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<ProfileDto> findByHandle(String handle) {
        return repository.findByHandle(handle.toLowerCase(Locale.ROOT)).map(this::toDto);
    }

    @Override
    @Transactional(readOnly = true)
    public Map<UUID, ProfileDto> findByIds(Collection<UUID> ids) {
        if (ids.isEmpty()) {
            return Map.of();
        }
        List<UserProfile> found = repository.findByIdIn(ids);
        // One extra query for the whole batch, and only when a business is in it —
        // feed decoration must not turn into a query per author.
        List<UUID> businessIds = found.stream()
            .filter(p -> p.getKind() == ProfileKind.BUSINESS)
            .map(UserProfile::getId)
            .toList();
        Map<UUID, BusinessProfile> extras = businessIds.isEmpty() ? Map.of()
            : businesses.findAllById(businessIds).stream()
                .collect(Collectors.toMap(BusinessProfile::getProfileId, Function.identity()));
        return found.stream()
            .map(p -> toDto(p, extras.get(p.getId())))
            .collect(Collectors.toMap(ProfileDto::id, Function.identity()));
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<BusinessProfileDto> findBusiness(UUID profileId) {
        return businesses.findById(profileId).map(ProfileService::toBusinessDto);
    }

    @Override
    @Transactional(readOnly = true)
    public List<ProfileDto> businessesOwnedBy(UUID ownerProfileId) {
        return businesses.findByOwnerProfileIdOrderByCreatedAtDesc(ownerProfileId).stream()
            .flatMap(b -> repository.findById(b.getProfileId()).map(p -> toDto(p, b)).stream())
            .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public UUID requireActingProfile(UUID callerProfileId, UUID actAsProfileId) {
        if (actAsProfileId == null || actAsProfileId.equals(callerProfileId)) {
            return callerProfileId;
        }
        BusinessProfile business = businesses.findById(actAsProfileId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.FORBIDDEN,
                "You can only post as a business profile you own."));
        if (!business.getOwnerProfileId().equals(callerProfileId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                "You can only post as a business profile you own.");
        }
        return actAsProfileId;
    }

    @Override
    @Transactional
    public void setBusinessVerified(UUID businessProfileId, boolean verified) {
        businesses.findById(businessProfileId).ifPresent(business -> {
            business.setVerified(verified);
            businesses.save(business);
        });
    }

    @Transactional
    ProfileDto updateOwn(String cognitoSub, String email, UpdateProfileRequest request) {
        UserProfile profile = repository.findByCognitoSub(cognitoSub)
            .orElseGet(() -> repository.saveAndFlush(new UserProfile(cognitoSub, email, generateHandle(email))));
        if (request.displayName() != null) {
            profile.setDisplayName(request.displayName());
        }
        if (request.handle() != null) {
            applyHandleChange(profile, request.handle());
        }
        if (request.bio() != null) {
            profile.setBio(request.bio());
        }
        if (request.category() != null) {
            profile.setCategory(request.category());
        }
        if (request.birthYear() != null) {
            profile.setBirthYear(request.birthYear());
        }
        if (request.avatarUrl() != null) {
            String avatar = request.avatarUrl().isBlank() ? null : request.avatarUrl();
            profile.setAvatarUrl(avatar);
            if (avatar != null) {
                events.publishEvent(new ProfileAvatarChanged(profile.getId(), avatar));
            }
        }
        if (request.interests() != null) {
            profile.setInterests(request.interests());
        }
        return toDto(repository.save(profile));
    }

    /** Dedicated username-change endpoint — same rules as PATCH, handle-only. */
    @Transactional
    ProfileDto changeHandle(String cognitoSub, String email, String requestedHandle) {
        UserProfile profile = repository.findByCognitoSub(cognitoSub)
            .orElseGet(() -> repository.saveAndFlush(new UserProfile(cognitoSub, email, generateHandle(email))));
        applyHandleChange(profile, requestedHandle);
        return toDto(repository.save(profile));
    }

    @Transactional(readOnly = true)
    HandleStatusResponse handleStatus(String cognitoSub, String email) {
        UserProfile profile = repository.findByCognitoSub(cognitoSub)
            .orElseGet(() -> new UserProfile(cognitoSub, email, ""));
        OffsetDateTime last = profile.getHandleChangedAt();
        boolean inFreeTier = profile.getHandleChangeCount() < FREE_HANDLE_SETS;
        OffsetDateTime availableAt = (inFreeTier || last == null) ? null : last.plus(HANDLE_CHANGE_COOLDOWN);
        boolean canChangeNow = availableAt == null || !OffsetDateTime.now().isBefore(availableAt);
        return new HandleStatusResponse(profile.getHandle(), last,
            canChangeNow ? null : availableAt, canChangeNow);
    }

    @Transactional(readOnly = true)
    HandleAvailabilityResponse handleAvailability(String cognitoSub, String rawHandle) {
        String normalized = normalizeHandle(rawHandle == null ? "" : rawHandle);
        if (normalized.length() < HANDLE_MIN_LENGTH) {
            return new HandleAvailabilityResponse(false, "invalid", normalized);
        }
        String currentHandle = repository.findByCognitoSub(cognitoSub)
            .map(UserProfile::getHandle).orElse(null);
        if (normalized.equals(currentHandle)) {
            return new HandleAvailabilityResponse(false, "current", normalized);
        }
        if (repository.existsByHandle(normalized)) {
            return new HandleAvailabilityResponse(false, "taken", normalized);
        }
        return new HandleAvailabilityResponse(true, "ok", normalized);
    }

    /**
     * Central handle-change guard — every path (PATCH, dedicated endpoint) goes
     * through here so the cooldown can't be bypassed. Rules:
     *   • no-op if the normalized handle equals the current one;
     *   • the first {@link #FREE_HANDLE_SETS} sets are free (onboarding pick + one grace);
     *   • after that, a change requires {@link #HANDLE_CHANGE_COOLDOWN} since the last change;
     *   • the target must be a valid, un-taken handle.
     */
    private void applyHandleChange(UserProfile profile, String requestedHandle) {
        String handle = normalizeHandle(requestedHandle);
        if (handle.length() < HANDLE_MIN_LENGTH) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Username must be at least " + HANDLE_MIN_LENGTH + " characters (letters, numbers, _ or .).");
        }
        if (handle.equals(profile.getHandle())) {
            return; // unchanged — not a "change", doesn't consume a free set or the cooldown
        }
        boolean inFreeTier = profile.getHandleChangeCount() < FREE_HANDLE_SETS;
        OffsetDateTime last = profile.getHandleChangedAt();
        if (!inFreeTier && last != null) {
            OffsetDateTime availableAt = last.plus(HANDLE_CHANGE_COOLDOWN);
            if (OffsetDateTime.now().isBefore(availableAt)) {
                throw new HandleChangeCooldownException(availableAt);
            }
        }
        if (repository.existsByHandle(handle)) {
            throw new HandleTakenException(handle);
        }
        profile.setHandle(handle);
        profile.recordHandleChange();
    }

    private String generateHandle(String email) {
        return uniqueHandle(email == null ? "user" : email.split("@")[0]);
    }

    /** Turns any free text into a handle nobody has taken yet. */
    String uniqueHandle(String rawBase) {
        String base = normalizeHandle(rawBase);
        if (base.length() < HANDLE_MIN_LENGTH) {
            base = "gojo" + base;
        }
        String candidate = base;
        while (repository.existsByHandle(candidate)) {
            candidate = base + ThreadLocalRandom.current().nextInt(1000, 10000);
        }
        return candidate;
    }

    private static String normalizeHandle(String raw) {
        return Handles.normalize(raw);
    }

    private ProfileDto toDto(UserProfile p) {
        return toDto(p, p.getKind() == ProfileKind.BUSINESS
            ? businesses.findById(p.getId()).orElse(null)
            : null);
    }

    static ProfileDto toDto(UserProfile p, BusinessProfile business) {
        return new ProfileDto(p.getId(), p.getCognitoSub(), p.getEmail(), p.getDisplayName(),
            p.getHandle(), p.getBio(), p.getCategory(), p.getBirthYear(), p.getAvatarUrl(),
            Set.copyOf(p.getInterests()), p.getKind(),
            business == null ? null : business.getOwnerProfileId(),
            business != null && business.isVerified());
    }

    static BusinessProfileDto toBusinessDto(BusinessProfile b) {
        return new BusinessProfileDto(b.getProfileId(), b.getOwnerProfileId(),
            b.getContactPhone(), b.getContactEmail(), b.getWebsiteUrl(),
            b.getAddressLine(), b.getCity(), b.getCountry(), b.getLatitude(), b.getLongitude(),
            b.getOpeningHours(), b.isVerified());
    }
}
