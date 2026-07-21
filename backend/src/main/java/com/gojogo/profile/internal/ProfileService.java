package com.gojogo.profile.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

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
                    return repository.saveAndFlush(new UserProfile(cognitoSub, email));
                } catch (DataIntegrityViolationException raceWithConcurrentFirstLogin) {
                    return repository.findByCognitoSub(cognitoSub).orElseThrow();
                }
            });
        return new ProfileDto(profile.getId(), profile.getCognitoSub(), profile.getEmail(), profile.getDisplayName());
    }
}
