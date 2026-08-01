package com.gojogo.social.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import com.gojogo.profile.ProfileKind;
import com.gojogo.social.UserFollowed;
import com.gojogo.storefront.StorefrontApi;
import com.gojogo.storefront.StorefrontDocument;
import com.gojogo.storefront.StorefrontSurface;
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
    private final BlockService blocks;
    private final ProfileApi profiles;
    private final StorefrontApi storefronts;
    private final ApplicationEventPublisher events;

    FollowService(FollowRepository follows, PostRepository posts, BlockService blocks,
                  ProfileApi profiles, StorefrontApi storefronts,
                  ApplicationEventPublisher events) {
        this.follows = follows;
        this.posts = posts;
        this.blocks = blocks;
        this.profiles = profiles;
        this.storefronts = storefronts;
        this.events = events;
    }

    @Transactional
    void follow(UUID me, UUID followeeId) {
        if (me.equals(followeeId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Cannot follow yourself");
        }
        requireProfile(followeeId);
        // Following back across a block would undo it silently — and the person
        // being followed would get a notification naming someone they blocked.
        if (blocks.between(me, followeeId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such profile");
        }
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
        // **Only one half of a block is disclosed.** If I blocked them, the
        // screen has to say so — it is the only place I can undo it. If *they*
        // blocked me, the profile is simply not there: telling someone they were
        // blocked hands them a reason to open a second account, and "this
        // account is unavailable" is what every product settled on.
        boolean iBlocked = blocks.iBlocked(me, profileId);
        if (!iBlocked && blocks.between(me, profileId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such profile");
        }
        String name = profile.displayName() != null ? profile.displayName() : profile.handle();
        // A business is a profile, so this is the public read for one too — the
        // extra block is the only difference, and it's null for a person.
        BusinessBlock business = profile.kind() == ProfileKind.BUSINESS
            ? profiles.findBusiness(profileId).map(b -> new BusinessBlock(b.ownerProfileId(),
                b.contactPhone(), b.contactEmail(), b.websiteUrl(), b.addressLine(),
                b.city(), b.country(), b.latitude(), b.longitude(), b.openingHours())).orElse(null)
            : null;
        // The home page a business arranged for itself (SPECS §9). Read here
        // because this is where a profile is rendered from and a business is a
        // profile — but only for a business: a person has no home document, and
        // asking for one on every profile view would be a query per read to
        // learn nothing.
        StorefrontDocument home = business == null
            ? StorefrontDocument.empty()
            : storefronts.documentFor(StorefrontSurface.BUSINESS_HOME, profileId);
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
            follows.existsById(new Follow.Key(me, profileId)),
            profile.kind().name(),
            profile.verified(),
            business != null && me.equals(business.ownerProfileId()),
            business,
            home,
            iBlocked);
    }

    private ProfileDto requireProfile(UUID profileId) {
        return profiles.findById(profileId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such profile"));
    }
}
