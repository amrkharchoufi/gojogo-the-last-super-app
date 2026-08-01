package com.gojogo.social.internal;

import com.gojogo.social.SocialGraphApi;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/** The {@link SocialGraphApi} implementation — the only way out of this module. */
@Service
class SocialGraphService implements SocialGraphApi {

    private final FollowRepository follows;
    private final BlockService blocks;

    SocialGraphService(FollowRepository follows, BlockService blocks) {
        this.follows = follows;
        this.blocks = blocks;
    }

    @Override
    @Transactional(readOnly = true)
    public Set<UUID> followeeIds(UUID userId) {
        return userId == null ? Set.of() : follows.followeeIds(userId);
    }

    @Override
    @Transactional(readOnly = true)
    public Map<UUID, Long> followerCounts(Collection<UUID> profileIds) {
        if (profileIds == null || profileIds.isEmpty()) {
            return Map.of();
        }
        Set<UUID> wanted = new LinkedHashSet<>(profileIds);
        Map<UUID, Long> counts = new HashMap<>();
        // Zero-fill first so the caller can distinguish "no followers" from
        // "not asked about" — the grouped query only returns non-empty rows.
        for (UUID id : wanted) {
            counts.put(id, 0L);
        }
        for (Object[] row : follows.followerCounts(wanted)) {
            counts.put((UUID) row[0], (Long) row[1]);
        }
        return counts;
    }

    @Override
    @Transactional(readOnly = true)
    public Set<UUID> blockedIds(UUID userId) {
        return blocks.hiddenFrom(userId);
    }

    @Override
    @Transactional(readOnly = true)
    public boolean blockedBetween(UUID a, UUID b) {
        return blocks.between(a, b);
    }
}
