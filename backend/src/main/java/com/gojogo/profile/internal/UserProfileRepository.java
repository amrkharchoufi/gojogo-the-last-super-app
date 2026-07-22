package com.gojogo.profile.internal;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

interface UserProfileRepository extends JpaRepository<UserProfile, UUID> {

    Optional<UserProfile> findByCognitoSub(String cognitoSub);

    boolean existsByHandle(String handle);

    Optional<UserProfile> findByHandle(String handle);

    List<UserProfile> findByIdIn(Collection<UUID> ids);
}
