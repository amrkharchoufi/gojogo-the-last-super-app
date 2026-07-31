package com.gojogo.storefront.internal;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

interface StorefrontRepository extends JpaRepository<StoredStorefront, UUID> {

    Optional<StoredStorefront> findBySurfaceAndOwnerId(String surface, UUID ownerId);

    List<StoredStorefront> findBySurfaceAndOwnerIdIn(String surface, Set<UUID> ownerIds);
}
