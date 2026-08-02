package com.gojogo.messaging.internal;

import com.gojogo.messaging.internal.MessagingRepository.Circle;
import com.gojogo.messaging.internal.MessagingRepository.ContactEdge;
import com.gojogo.messaging.internal.MessagingRepository.WorldProfile;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * The GojoMessages graph: contacts reached by phone number, circles as the
 * audience primitive, and the rich profile hanging off the phone-verified
 * identity.
 *
 * <p>Two rules hold everywhere in here. <b>A number is the only way in</b> —
 * there is no handle lookup, because a handle is how the public network finds
 * you and a number is how your friends do. And <b>a circle is an audience</b>,
 * not a folder: a circle may only contain people you actually have as contacts,
 * so publishing to one can never reach somebody outside your graph.
 */
@Service
class WorldGraphService {

    private final MessagingRepository repo;

    WorldGraphService(MessagingRepository repo) {
        this.repo = repo;
    }

    // ---- contacts ---------------------------------------------------------

    ContactDto addContact(UUID ownerId, String rawPhone, String alias) {
        String phone = WorldService.normalize(rawPhone);
        UUID contactId = repo.profileIdForPhone(phone)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Nobody on GojoMessages has that number yet"));
        if (contactId.equals(ownerId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "That's your own number");
        }
        repo.addContact(ownerId, contactId, phone);
        // Adding somebody joins their audience, and an audience you joined a
        // minute ago should not start empty. Content is fanned out on write, so
        // without this the add delivers only what they publish *next* — they
        // read as somebody who has never posted, indefinitely, while whoever
        // added *you* first has been seeing your posts all along.
        repo.deliverBacklog(ownerId, contactId);
        if (alias != null && !alias.isBlank()) {
            repo.putAlias(ownerId, contactId, alias.trim());
        }
        WorldProfile p = repo.getWorldProfile(contactId).orElse(null);
        return new ContactDto(contactId,
            p != null ? p.displayName() : null,
            p != null ? p.avatarUrl() : null,
            phone,
            repo.getAlias(ownerId, contactId).orElse(null),
            Instant.now());
    }

    void removeContact(UUID ownerId, UUID contactId) {
        repo.removeContact(ownerId, contactId);
        // What the add handed over goes back with it: keeping their posts in a
        // feed built out of a number you no longer have would leave the graph
        // and the feed disagreeing about who is in the audience.
        repo.withdrawBacklog(ownerId, contactId);
        // The rename goes with the contact: keeping it would resurrect a private
        // name for somebody you deliberately dropped.
        repo.deleteAlias(ownerId, contactId);
        // Circles are audiences, so a dropped contact must leave them in the same
        // breath — otherwise the next post to that circle reaches someone who is
        // no longer in the graph.
        for (Circle circle : repo.listCircles(ownerId)) {
            if (!circle.memberIds().contains(contactId)) continue;
            List<UUID> remaining = circle.memberIds().stream()
                .filter(id -> !id.equals(contactId)).toList();
            repo.putCircle(ownerId, new Circle(circle.id(), circle.name(),
                circle.colorHex(), remaining, circle.createdAt()));
        }
    }

    List<ContactDto> listContacts(UUID ownerId) {
        List<ContactEdge> edges = repo.listContacts(ownerId);
        List<ContactDto> out = new ArrayList<>(edges.size());
        for (ContactEdge e : edges) {
            WorldProfile p = repo.getWorldProfile(e.contactId()).orElse(null);
            out.add(new ContactDto(e.contactId(),
                p != null ? p.displayName() : null,
                p != null ? p.avatarUrl() : null,
                p != null ? p.phone() : null,
                e.alias(),
                e.addedAt()));
        }
        return out;
    }

    // ---- circles ----------------------------------------------------------

    List<CircleDto> listCircles(UUID ownerId) {
        return repo.listCircles(ownerId).stream()
            .map(c -> new CircleDto(c.id(), c.name(), c.colorHex(), c.memberIds(), c.createdAt()))
            .toList();
    }

    CircleDto createCircle(UUID ownerId, SaveCircleRequest req) {
        return saveCircle(ownerId, UUID.randomUUID(), req, Instant.now());
    }

    CircleDto updateCircle(UUID ownerId, UUID circleId, SaveCircleRequest req) {
        Circle existing = repo.getCircle(ownerId, circleId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such circle"));
        return saveCircle(ownerId, circleId, req, existing.createdAt());
    }

    private CircleDto saveCircle(UUID ownerId, UUID circleId, SaveCircleRequest req, Instant created) {
        List<UUID> members = req.memberIds() == null ? List.of() : req.memberIds();
        // A circle is an audience: everyone in it must be someone you actually
        // have. Refused rather than silently filtered, so a caller can't believe
        // it published to somebody it didn't.
        for (UUID member : members) {
            if (!repo.isContact(ownerId, member)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A circle can only contain your contacts");
            }
        }
        List<UUID> deduped = new ArrayList<>(new LinkedHashSet<>(members));
        repo.putCircle(ownerId, new Circle(circleId, req.name().trim(),
            req.colorHex(), deduped, created));
        return new CircleDto(circleId, req.name().trim(), req.colorHex(), deduped, created);
    }

    void deleteCircle(UUID ownerId, UUID circleId) {
        repo.deleteCircle(ownerId, circleId);
    }

    /**
     * Everyone who may read something published to this audience. Content is
     * fanned out to exactly this list, which is what keeps the read path free of
     * any filter that could be forgotten.
     */
    Set<UUID> resolveAudience(UUID authorId, WorldAudience audience, List<UUID> circleIds) {
        if (audience == WorldAudience.CONTACTS) {
            return new LinkedHashSet<>(repo.followersOf(authorId));
        }
        if (circleIds == null || circleIds.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Pick at least one circle");
        }
        Set<UUID> viewers = new LinkedHashSet<>();
        for (UUID circleId : circleIds) {
            Circle circle = repo.getCircle(authorId, circleId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "No such circle"));
            viewers.addAll(circle.memberIds());
        }
        return viewers;
    }

    // ---- rich profile -----------------------------------------------------

    WorldRichProfileDto myProfile(UUID profileId) {
        return repo.getRichProfile(profileId).orElseGet(WorldRichProfileDto::empty);
    }

    WorldRichProfileDto updateProfile(UUID profileId, UpdateRichProfileRequest req) {
        WorldRichProfileDto updated = new WorldRichProfileDto(
            req.bio(), req.gender(), req.city(),
            orEmpty(req.languages()), req.education(), req.occupation(),
            orEmpty(req.interests()), orEmpty(req.favouriteBooks()), orEmpty(req.favouriteFilms()),
            orEmpty(req.favouriteTv()), orEmpty(req.favouriteSport()), orEmpty(req.favouriteGames()));
        repo.putRichProfile(profileId, updated);
        return updated;
    }

    /**
     * Somebody else's identity as a viewer sees it. The rich half is returned
     * only to an actual contact — knowing a number is how you reach someone, not
     * a licence to read where they went to school.
     *
     * <p>The number itself goes further, to anyone <em>they</em> reached first
     * (see {@link #reachedMeFirst}), and that is what makes adding somebody back
     * possible at all. A number is the only way into this graph, so somebody who
     * has yours and is messaging you is somebody you cannot add — the one person
     * it is most obviously right to add. Handing their number over is also even:
     * they already have yours, which is how they got here.
     */
    WorldContactProfileDto contactProfile(UUID viewerId, UUID contactId) {
        WorldProfile p = repo.getWorldProfile(contactId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Not found"));
        boolean contact = repo.isContact(viewerId, contactId);
        boolean mayHaveTheNumber = contact || reachedMeFirst(viewerId, contactId);
        return new WorldContactProfileDto(
            contactId, p.displayName(), p.avatarUrl(),
            mayHaveTheNumber ? p.phone() : null,
            repo.getAlias(viewerId, contactId).orElse(null),
            contact,
            contact ? myProfile(contactId) : null);
    }

    /**
     * Whether they came to you — they have you as a contact, or they have a
     * thread with you. Either one means they had your number, since a number is
     * the only way to reach anybody here. Nothing else counts: a group thread
     * would make everyone in a room a source of everyone else's number.
     */
    private boolean reachedMeFirst(UUID viewerId, UUID contactId) {
        return repo.isContact(contactId, viewerId)
            || repo.findDirectConversation(viewerId, contactId).isPresent();
    }

    private static List<String> orEmpty(List<String> in) {
        return in == null ? List.of() : in.stream().filter(v -> v != null && !v.isBlank()).toList();
    }
}
