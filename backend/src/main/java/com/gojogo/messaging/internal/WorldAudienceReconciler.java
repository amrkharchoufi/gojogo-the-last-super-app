package com.gojogo.messaging.internal;

import com.gojogo.messaging.internal.MessagingRepository.ContactEdge;
import com.gojogo.messaging.internal.MessagingRepository.StoredContent;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * One-off: brings feed copies written under the old audience rule in line with
 * the corrected one, once, on the deploy that corrects it.
 *
 * <p>A GojoMessages post used to go to everyone who had <em>added the author</em>.
 * As a sentence that sounds reasonable — "everyone who has my number" — and as a
 * permission it is backwards: anybody holding your number could add themselves
 * to your audience, and you had no way to take them out of it. The audience is
 * now the author's own contact list.
 *
 * <p>Content is fanned out on write, which is what keeps the read path free of
 * any filter that could be forgotten — and is exactly why changing the rule does
 * not reach backwards. Every copy delivered under the old rule is still sitting
 * in the partition it was written to. So this makes the delivered set equal the
 * intended set, both ways:
 *
 * <ul>
 *   <li>a copy held by somebody the author never added is <b>revoked</b> — that
 *       is the leftover disclosure, and the reason this runs at all;
 *   <li>a current contact who never got a post is <b>given</b> one, because
 *       "everyone you added" has to include the ones you added before it;
 *   <li>the author copy's viewer list is rewritten to match, since that list is
 *       what a delete walks — a copy it doesn't name would outlive its post.
 * </ul>
 *
 * <p><b>Circle posts are left alone.</b> A circle is an audience the author
 * picked by hand, name by name, and nothing about the contacts rule changes who
 * was picked.
 *
 * <p>Runs once ever, guarded by a marker row, and is idempotent regardless: a
 * second pass finds nothing to do. The marker is written <em>after</em> the work
 * rather than before, so a task that dies mid-pass leaves the job to be redone
 * rather than recorded as finished.
 */
@Component
class WorldAudienceReconciler {

    private static final Logger log = LoggerFactory.getLogger(WorldAudienceReconciler.class);

    /** Bump the suffix to make it run again. */
    private static final String MIGRATION = "world-audience-author-picks-v1";

    private final MessagingRepository repo;
    private final MessagingProperties props;

    WorldAudienceReconciler(MessagingRepository repo, MessagingProperties props) {
        this.repo = repo;
        this.props = props;
    }

    @EventListener(ApplicationReadyEvent.class)
    void reconcileOnce() {
        // Messaging off on this environment means there is no table to walk —
        // not a failure, the same shape as every other call in this module.
        if (!props.enabled()) return;
        try {
            if (repo.migrationDone(MIGRATION)) return;
            String summary = reconcile();
            repo.markMigrationDone(MIGRATION, summary);
            log.info("GojoMessages audience reconciliation complete — {}", summary);
        } catch (RuntimeException e) {
            // Never take the application down for this. An unreconciled feed is
            // wrong in a way somebody can see; a backend that won't start is
            // wrong in a way everybody can.
            log.error("GojoMessages audience reconciliation failed — will retry next start", e);
        }
    }

    private String reconcile() {
        Instant now = Instant.now();
        Map<UUID, Set<UUID>> contactsByAuthor = new HashMap<>();
        int posts = 0, revoked = 0, delivered = 0;

        for (StoredContent c : repo.scanAllAuthorContent()) {
            if (!WorldAudience.CONTACTS.name().equals(c.audience())) continue;
            // An expired story is already gone to every reader; TTL sweeps the
            // row. Rewriting it would be churn against something on its way out.
            if (c.expiresAt() != null && c.expiresAt().isBefore(now)) continue;

            Set<UUID> intended = contactsByAuthor.computeIfAbsent(c.authorId(), author -> {
                Set<UUID> ids = new LinkedHashSet<>();
                for (ContactEdge e : repo.listContacts(author)) ids.add(e.contactId());
                ids.remove(author); // fan-out never writes the author their own copy
                return ids;
            });

            Set<UUID> had = new LinkedHashSet<>(c.viewers());
            List<UUID> toRevoke = had.stream().filter(v -> !intended.contains(v)).toList();
            List<UUID> toDeliver = intended.stream().filter(v -> !had.contains(v)).toList();
            if (toRevoke.isEmpty() && toDeliver.isEmpty()) continue;

            posts++;
            for (UUID viewer : toRevoke) {
                repo.deleteFeedCopy(viewer, c);
                revoked++;
            }
            for (UUID viewer : toDeliver) {
                repo.putFeedCopy(viewer, c);
                delivered++;
            }
            repo.recordViewers(c, new ArrayList<>(intended));
        }
        return "posts corrected: " + posts + ", copies revoked: " + revoked
            + ", copies delivered: " + delivered;
    }
}
