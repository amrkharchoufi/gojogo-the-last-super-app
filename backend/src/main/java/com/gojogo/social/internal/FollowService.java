package com.gojogo.social.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import com.gojogo.social.UserFollowed;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.UUID;

@Service
class FollowService {

    private final FollowRepository follows;
    private final PostRepository posts;
    private final ProfileApi profiles;
    private final ApplicationEventPublisher events;

    FollowService(FollowRepository follows, PostRepository posts, ProfileApi profiles,
                  ApplicationEventPublisher events) {
        this.follows = follows;
        this.posts = posts;
        this.profiles = profiles;
        this.events = events;
    }

    @Transactional
    void follow(UUID me, UUID followeeId) {
        if (me.equals(followeeId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Cannot follow yourself");
        }
        requireProfile(followeeId);
        try {
            follows.saveAndFlush(new Follow(me, followeeId));
            events.publishEvent(new UserFollowed(me, followeeId));
        } catch (DataIntegrityViolationException alreadyFollowing) {
            // idempotent
        }
    }

    @Transactional
    void unfollow(UUID me, UUID followeeId) {
        follows.deleteByFollowerIdAndFolloweeId(me, followeeId);
    }

    @Transactional(readOnly = true)
    ProfileViewResponse viewByHandle(UUID me, String handle) {
        ProfileDto profile = profiles.findByHandle(handle)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such profile"));
        return view(me, profile.id());
    }

    @Transactional(readOnly = true)
    ProfileViewResponse view(UUID me, UUID profileId) {
        ProfileDto profile = requireProfile(profileId);
        String name = profile.displayName() != null ? profile.displayName() : profile.handle();
        return new ProfileViewResponse(
            profile.id(),
            name,
            profile.handle(),
            profile.avatarUrl(),
            profile.bio(),
            profile.category(),
            posts.countByAuthorId(profileId),
            follows.countByFolloweeId(profileId),
            follows.countByFollowerId(profileId),
            me.equals(profileId),
            follows.existsById(new Follow.Key(me, profileId)));
    }

    private ProfileDto requireProfile(UUID profileId) {
        return profiles.findById(profileId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such profile"));
    }
}
