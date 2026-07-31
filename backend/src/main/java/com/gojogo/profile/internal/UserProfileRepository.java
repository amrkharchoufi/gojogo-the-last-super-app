package com.gojogo.profile.internal;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

interface UserProfileRepository extends JpaRepository<UserProfile, UUID> {

    Optional<UserProfile> findByCognitoSub(String cognitoSub);

    boolean existsByHandle(String handle);

    Optional<UserProfile> findByHandle(String handle);

    List<UserProfile> findByIdIn(Collection<UUID> ids);

    List<UserProfile> findByHandleIn(Collection<String> handles);

    /**
     * Picker search. Handle matches are prefix-only (you type the start of a
     * username), display-name matches are anywhere (you type a surname), and the
     * ordering puts handle hits first so a half-typed handle doesn't rank below
     * someone whose bio-name happens to contain the same letters.
     */
    @Query("""
        select p from UserProfile p
        where lower(p.handle) like concat(:q, '%')
           or lower(p.displayName) like concat('%', :q, '%')
        order by case when lower(p.handle) like concat(:q, '%') then 0 else 1 end,
                 length(p.handle), p.handle
        """)
    List<UserProfile> search(@Param("q") String query, Limit limit);
}
