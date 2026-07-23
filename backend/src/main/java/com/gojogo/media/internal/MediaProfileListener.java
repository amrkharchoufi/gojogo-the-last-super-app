package com.gojogo.media.internal;

import com.gojogo.profile.ProfileAvatarChanged;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.event.TransactionalEventListener;

import java.util.List;

/**
 * Marks a profile avatar's S3 object as referenced once the profile edit commits.
 * Uses an event (not a direct call) because media already depends on profile — a
 * profile→media call would be a module cycle.
 */
@Component
class MediaProfileListener {

    private final MediaReferenceService references;

    MediaProfileListener(MediaReferenceService references) {
        this.references = references;
    }

    @TransactionalEventListener
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void onAvatarChanged(ProfileAvatarChanged event) {
        references.markReferenced(List.of(event.avatarUrl()));
    }
}
