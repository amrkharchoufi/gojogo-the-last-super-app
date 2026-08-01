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

    /**
     * Accounts whose grace period has run out — the deletion sweep's only query.
     *
     * <p>Oldest request first, so a backlog after an outage is worked in the
     * order people asked, and batched with a {@link Limit} so one very bad day
     * cannot turn a nightly job into an hour-long transaction.
     */
    @Query("""
        select p from UserProfile p
        where p.deletionRequestedAt is not null
          and p.anonymizedAt is null
          and p.deletionRequestedAt < :cutoff
        order by p.deletionRequestedAt asc
        """)
    List<UserProfile> deletionsDue(@Param("cutoff") java.time.OffsetDateTime cutoff, Limit limit);
}
