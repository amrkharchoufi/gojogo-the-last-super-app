package com.gojogo.profile.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Collection;
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

    private final UserProfileRepository repository;

    ProfileService(UserProfileRepository repository) {
        this.repository = repository;
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
        return repository.findById(id).map(ProfileService::toDto);
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<ProfileDto> findByHandle(String handle) {
        return repository.findByHandle(handle.toLowerCase(Locale.ROOT)).map(ProfileService::toDto);
    }

    @Override
    @Transactional(readOnly = true)
    public Map<UUID, ProfileDto> findByIds(Collection<UUID> ids) {
        if (ids.isEmpty()) {
            return Map.of();
        }
        return repository.findByIdIn(ids).stream()
            .map(ProfileService::toDto)
            .collect(Collectors.toMap(ProfileDto::id, Function.identity()));
    }

    @Transactional
    ProfileDto updateOwn(String cognitoSub, String email, UpdateProfileRequest request) {
        UserProfile profile = repository.findByCognitoSub(cognitoSub)
            .orElseGet(() -> repository.saveAndFlush(new UserProfile(cognitoSub, email, generateHandle(email))));
        if (request.displayName() != null) {
            profile.setDisplayName(request.displayName());
        }
        if (request.handle() != null && !request.handle().equals(profile.getHandle())) {
            String handle = normalizeHandle(request.handle());
            if (repository.existsByHandle(handle)) {
                throw new HandleTakenException(handle);
            }
            profile.setHandle(handle);
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
            profile.setAvatarUrl(request.avatarUrl().isBlank() ? null : request.avatarUrl());
        }
        if (request.interests() != null) {
            profile.setInterests(request.interests());
        }
        return toDto(repository.save(profile));
    }

    private String generateHandle(String email) {
        String base = email == null ? "user" : normalizeHandle(email.split("@")[0]);
        if (base.isBlank()) {
            base = "user";
        }
        String candidate = base;
        while (repository.existsByHandle(candidate)) {
            candidate = base + ThreadLocalRandom.current().nextInt(1000, 10000);
        }
        return candidate;
    }

    private static String normalizeHandle(String raw) {
        String handle = raw.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9_.]", "");
        return handle.length() > 30 ? handle.substring(0, 30) : handle;
    }

    private static ProfileDto toDto(UserProfile p) {
        return new ProfileDto(p.getId(), p.getCognitoSub(), p.getEmail(), p.getDisplayName(),
            p.getHandle(), p.getBio(), p.getCategory(), p.getBirthYear(), p.getAvatarUrl(),
            Set.copyOf(p.getInterests()));
    }
}
