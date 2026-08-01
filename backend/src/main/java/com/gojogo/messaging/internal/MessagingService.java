package com.gojogo.messaging.internal;

import com.gojogo.messaging.internal.MessagingRepository.ConversationMeta;
import com.gojogo.messaging.internal.MessagingRepository.Membership;
import com.gojogo.messaging.internal.MessagingRepository.StoredMessage;
import com.gojogo.messaging.internal.MessagingRepository.WorldProfile;
import com.gojogo.media.MediaApi;
import com.gojogo.messaging.ConversationContext;
import com.gojogo.messaging.ConversationGuard;
import com.gojogo.messaging.MessageSent;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

/**
 * Messaging business logic: authorization (a caller must be a participant),
 * conversation/message CRUD over {@link MessagingRepository}, and WebSocket
 * fan-out of every state change via {@link Fanout}. All durable writes happen
 * here; the client sends over REST and receives over the socket.
 */
@Service
class MessagingService {

    private final MessagingRepository repo;
    private final ProfileApi profiles;
    private final Fanout fanout;
    private final MediaApi media;
    private final ApplicationEventPublisher events;
    /** Whoever gets a say in whether two people may be put in a thread — today
     *  just blocking, from {@code social}. Empty is a valid state. */
    private final List<ConversationGuard> guards;

    MessagingService(MessagingRepository repo, ProfileApi profiles, Fanout fanout, MediaApi media,
                     ApplicationEventPublisher events, List<ConversationGuard> guards) {
        this.repo = repo;
        this.profiles = profiles;
        this.fanout = fanout;
        this.media = media;
        this.events = events;
        this.guards = guards;
    }

    // ---- conversations ----------------------------------------------------

    List<ConversationDto> listConversations(UUID userId) {
        List<Membership> memberships = repo.listMemberships(userId);
        List<ConversationDto> out = new ArrayList<>(memberships.size());
        for (Membership m : memberships) {
            repo.getConversation(m.conversationId())
                .ifPresent(meta -> out.add(toConversationDto(meta, m)));
        }
        return out;
    }

    ConversationDto createConversation(UUID userId, CreateConversationRequest req) {
        return createConversation(userId, req, null);
    }

    ConversationDto createConversation(UUID userId, CreateConversationRequest req,
                                       ConversationContext context) {
        Set<UUID> participants = new LinkedHashSet<>(req.participantIds());
        participants.add(userId);
        if (participants.size() < 2) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "A conversation needs at least one other participant");
        }
        List<UUID> ordered = new ArrayList<>(participants);
        boolean isDirect = ordered.size() == 2 && req.circleId() == null;

        // Asked before the reuse path below, so a thread that already exists
        // cannot be walked back into after a block. Reaching an existing
        // conversation is opening one.
        for (ConversationGuard guard : guards) {
            String refusal = guard.refuseConversation(userId, ordered);
            if (refusal != null) {
                throw new ResponseStatusException(HttpStatus.FORBIDDEN, refusal);
            }
        }

        if (isDirect) {
            // The DIRECT#a#b pointer outlives the conversation it names: leaving a
            // 1:1 drops the membership row but nothing rewrites the pointer. Only
            // reuse it when the thread is really still there and still ours —
            // otherwise fall through and create a fresh one, which overwrites it.
            Optional<ConversationMeta> reusable = repo
                .findDirectConversation(ordered.get(0), ordered.get(1))
                .flatMap(repo::getConversation)
                .filter(meta -> meta.participants().contains(userId));
            if (reusable.isPresent()) {
                // A thread reused from a listing refreshes its card to the one the
                // buyer is asking about now; both sides see the update on next fetch.
                ConversationMeta meta = reusable.get();
                if (context != null) {
                    repo.updateContext(meta.id(), context);
                    meta = withContext(meta, context);
                }
                ConversationMeta resolved = meta;
                // Re-opening a thread you left puts it back in your list.
                Membership m = repo.getMembership(userId, resolved.id())
                    .orElseGet(() -> repo.rejoin(userId, resolved));
                return toConversationDto(resolved, m);
            }
        }

        Instant now = Instant.now();
        ConversationMeta meta = new ConversationMeta(
            UUID.randomUUID(),
            isDirect ? "DIRECT" : "GROUP",
            req.title(),
            ordered,
            req.circleId(),
            req.background(),
            userId,
            now,
            now,
            null,
            context);
        repo.createConversation(meta);
        Membership m = repo.getMembership(userId, meta.id()).orElseThrow(() -> gone(meta.id()));

        // Let the other participants' devices learn about the new thread.
        fanout.publish(otherThan(ordered, userId),
            Map.of("type", "conversation", "conversation",
                toConversationDto(meta, syntheticMembership(meta))));
        return toConversationDto(meta, m);
    }

    // ---- messages ---------------------------------------------------------

    MessagesResponse listMessages(UUID userId, UUID convId, Instant before, int limit) {
        ConversationMeta meta = requireParticipant(userId, convId);
        int capped = Math.min(Math.max(limit, 1), 50);
        List<StoredMessage> stored = repo.listMessages(convId, before, capped);
        List<UUID> senderIds = stored.stream().map(StoredMessage::senderId).toList();
        Map<UUID, ProfileDto> authors = profiles.findByIds(senderIds);
        Map<UUID, WorldProfile> worlds = repo.worldProfilesByIds(senderIds);
        List<MessageDto> messages = stored.stream().map(sm -> toMessageDto(sm, authors, worlds)).toList();
        Instant nextBefore = stored.size() == capped && !stored.isEmpty()
            ? stored.get(stored.size() - 1).createdAt() : null;
        UUID peerReadMessageId = peerReadCutoff(userId, convId, meta);
        return new MessagesResponse(messages, nextBefore, peerReadMessageId);
    }

    /**
     * The newest message every OTHER participant has read up to — i.e. the "Read"
     * high-water mark for the caller's own messages. Null while anyone still has
     * the caller's messages unread, so a group only shows "Read" once everyone has
     * seen it. Read state lives in each participant's membership row, so this is a
     * cheap point lookup per peer; it lets the receipt survive a reload instead of
     * relying on a live socket event the sender may have been offline for.
     */
    private UUID peerReadCutoff(UUID userId, UUID convId, ConversationMeta meta) {
        Instant slowest = null;
        UUID slowestId = null;
        for (UUID participant : meta.participants()) {
            if (participant.equals(userId)) continue;
            UUID lastRead = repo.getMembership(participant, convId)
                .map(Membership::lastReadMessageId).orElse(null);
            if (lastRead == null) return null; // this peer has read nothing yet
            Instant at = repo.getMessage(convId, lastRead)
                .map(StoredMessage::createdAt).orElse(null);
            if (at == null) continue; // pointer to a message we can't see; treat as caught up
            if (slowest == null || at.isBefore(slowest)) {
                slowest = at;
                slowestId = lastRead;
            }
        }
        return slowestId;
    }

    MessageDto sendMessage(UUID userId, UUID convId, SendMessageRequest req) {
        ConversationMeta meta = requireParticipant(userId, convId);
        ReplySnippetDto reply = buildReply(convId, req.replyToMessageId());

        // Send-later: store hidden until due; the scheduler delivers + fans out
        // at the scheduled time so recipients don't see it early. A small skew
        // guard treats "now-ish" as immediate.
        boolean deferred = req.scheduledAt() != null
            && req.scheduledAt().isAfter(Instant.now().plusSeconds(5));
        Instant createdAt = deferred ? req.scheduledAt() : Instant.now();
        StoredMessage msg = new StoredMessage(
            UUID.randomUUID(), convId, userId, req.kind(),
            req.text(), req.mediaItems(), req.poll(), reply,
            Map.of(), createdAt, req.scheduledAt(), req.clientId());

        if (req.mediaItems() != null && !req.mediaItems().isEmpty()) {
            media.markReferenced(req.mediaItems().stream()
                .flatMap(item -> java.util.stream.Stream.of(item.imageUrl(), item.videoUrl()))
                .toList());
        }

        if (deferred) {
            repo.putScheduledMessage(msg);
            return toMessageDto(msg, profiles.findByIds(List.of(userId)),
                repo.worldProfilesByIds(List.of(userId)));
        }

        repo.appendMessage(msg, meta.participants());
        MessageDto dto = toMessageDto(msg, profiles.findByIds(List.of(userId)),
            repo.worldProfilesByIds(List.of(userId)));
        fanout.publish(meta.participants(), Map.of("type", "message", "message", dto));
        notifyRecipients(meta, msg);
        return dto;
    }

    /** Fire a push to everyone but the sender (offline devices the socket missed). */
    private void notifyRecipients(ConversationMeta meta, StoredMessage msg) {
        List<UUID> recipients = otherThan(meta.participants(), msg.senderId());
        if (recipients.isEmpty()) return;
        events.publishEvent(new MessageSent(msg.conversationId(), msg.senderId(),
            worldName(msg.senderId()), snippet(msg), recipients));
    }

    private ReplySnippetDto buildReply(UUID convId, UUID replyToMessageId) {
        if (replyToMessageId == null) return null;
        return repo.getMessage(convId, replyToMessageId)
            .map(rm -> new ReplySnippetDto(rm.id(), worldName(rm.senderId()), snippet(rm)))
            .orElse(null);
    }

    /** Prefer the World display name (fallback to the social profile). */
    private String worldName(UUID profileId) {
        WorldProfile w = repo.getWorldProfile(profileId).orElse(null);
        if (w != null && w.displayName() != null) return w.displayName();
        ProfileDto p = profiles.findById(profileId).orElse(null);
        return p != null && p.displayName() != null ? p.displayName() : "Someone";
    }

    /** Delivers scheduled messages whose time has come (called by the poller). */
    void deliverDueScheduled() {
        for (var due : repo.listDueScheduled(Instant.now(), 25)) {
            if (!repo.claimScheduled(due.scheduleKey())) continue; // another instance won
            StoredMessage m = due.message();
            ConversationMeta meta = repo.getConversation(m.conversationId()).orElse(null);
            if (meta == null) continue;
            StoredMessage delivered = new StoredMessage(m.id(), m.conversationId(), m.senderId(),
                m.kind(), m.text(), m.mediaItems(), m.poll(), m.replyTo(), Map.of(),
                Instant.now(), null, m.clientId());
            repo.appendMessage(delivered, meta.participants());
            MessageDto dto = toMessageDto(delivered, profiles.findByIds(List.of(m.senderId())),
                repo.worldProfilesByIds(List.of(m.senderId())));
            fanout.publish(meta.participants(), Map.of("type", "message", "message", dto));
            notifyRecipients(meta, delivered);
        }
    }

    // ---- reactions --------------------------------------------------------

    void react(UUID userId, UUID convId, UUID msgId, String tapback) {
        ConversationMeta meta = requireParticipant(userId, convId);
        repo.setReaction(convId, msgId, userId, tapback);
        fanout.publish(meta.participants(), Map.of(
            "type", "reaction", "conversationId", convId, "messageId", msgId,
            "userId", userId, "tapback", tapback));
    }

    void unreact(UUID userId, UUID convId, UUID msgId) {
        ConversationMeta meta = requireParticipant(userId, convId);
        repo.clearReaction(convId, msgId, userId);
        Map<String, Object> event = new LinkedHashMap<>();
        event.put("type", "reaction");
        event.put("conversationId", convId);
        event.put("messageId", msgId);
        event.put("userId", userId);
        event.put("tapback", null);
        fanout.publish(meta.participants(), event);
    }

    // ---- polls ------------------------------------------------------------

    MessageDto votePoll(UUID userId, UUID convId, UUID msgId, UUID optionId) {
        ConversationMeta meta = requireParticipant(userId, convId);
        StoredMessage stored = repo.getMessage(convId, msgId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Message not found"));
        if (stored.poll() == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Message has no poll");
        }
        PollDto updated = applyVote(stored.poll(), optionId, userId);
        repo.updatePoll(convId, msgId, updated);

        StoredMessage revised = new StoredMessage(stored.id(), convId, stored.senderId(),
            stored.kind(), stored.text(), stored.mediaItems(), updated, stored.replyTo(),
            stored.reactions(), stored.createdAt(), stored.scheduledAt(), stored.clientId());
        MessageDto dto = toMessageDto(revised, profiles.findByIds(List.of(stored.senderId())),
            repo.worldProfilesByIds(List.of(stored.senderId())));
        fanout.publish(meta.participants(), Map.of("type", "poll", "message", dto));
        return dto;
    }

    private PollDto applyVote(PollDto poll, UUID optionId, UUID userId) {
        List<PollOptionDto> options = new ArrayList<>();
        for (PollOptionDto opt : poll.options()) {
            List<UUID> voters = opt.voters() == null ? new ArrayList<>() : new ArrayList<>(opt.voters());
            boolean isTarget = opt.id().equals(optionId);
            if (isTarget) {
                if (voters.contains(userId)) voters.remove(userId);
                else voters.add(userId);
            } else if (!poll.allowsMultiple()) {
                voters.remove(userId);
            }
            options.add(new PollOptionDto(opt.id(), opt.text(), voters));
        }
        return new PollDto(poll.question(), options, poll.allowsMultiple());
    }

    // ---- read / typing / pin / leave -------------------------------------

    void markRead(UUID userId, UUID convId, UUID lastReadMessageId) {
        ConversationMeta meta = requireParticipant(userId, convId);
        repo.markRead(userId, convId, lastReadMessageId);
        fanout.publish(otherThan(meta.participants(), userId), Map.of(
            "type", "read", "conversationId", convId,
            "userId", userId, "lastReadMessageId", lastReadMessageId));
    }

    void typing(UUID userId, UUID convId) {
        ConversationMeta meta = requireParticipant(userId, convId);
        fanout.publish(otherThan(meta.participants(), userId), Map.of(
            "type", "typing", "conversationId", convId, "userId", userId));
    }

    void setPinned(UUID userId, UUID convId, boolean pinned) {
        requireParticipant(userId, convId);
        repo.setPinned(userId, convId, pinned);
    }

    void leave(UUID userId, UUID convId) {
        repo.deleteMembership(userId, convId);
    }

    // ---- mapping / helpers ------------------------------------------------

    private ConversationMeta requireParticipant(UUID userId, UUID convId) {
        ConversationMeta meta = repo.getConversation(convId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Conversation not found"));
        if (!meta.participants().contains(userId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not a participant");
        }
        return meta;
    }

    private ConversationDto toConversationDto(ConversationMeta meta, Membership m) {
        Map<UUID, ProfileDto> people = profiles.findByIds(meta.participants());
        Map<UUID, WorldProfile> worlds = repo.worldProfilesByIds(meta.participants());
        List<ParticipantDto> participants = meta.participants().stream()
            .map(id -> {
                // Prefer the World identity (name/avatar) over the social profile.
                WorldProfile w = worlds.get(id);
                ProfileDto p = people.get(id);
                String name = w != null && w.displayName() != null ? w.displayName()
                    : (p != null ? p.displayName() : null);
                String avatar = w != null && w.avatarUrl() != null ? w.avatarUrl()
                    : (p != null ? p.avatarUrl() : null);
                String handle = p != null ? p.handle() : null;
                return new ParticipantDto(id, name, handle, avatar);
            })
            .toList();
        boolean isGroup = !"DIRECT".equals(meta.type());
        return new ConversationDto(
            meta.id(), meta.type().toLowerCase(), meta.title(), isGroup,
            participants, meta.circleId(), meta.background(),
            m.preview(), m.lastActivityAt(), m.unread(), m.pinned(), m.muted(),
            meta.context());
    }

    private static ConversationMeta withContext(ConversationMeta meta, ConversationContext context) {
        return new ConversationMeta(meta.id(), meta.type(), meta.title(), meta.participants(),
            meta.circleId(), meta.background(), meta.createdBy(), meta.createdAt(),
            meta.lastActivityAt(), meta.preview(), context);
    }

    private MessageDto toMessageDto(StoredMessage sm, Map<UUID, ProfileDto> authors,
                                    Map<UUID, WorldProfile> worlds) {
        ProfileDto author = authors.get(sm.senderId());
        WorldProfile world = worlds.get(sm.senderId());
        String senderName = world != null && world.displayName() != null ? world.displayName()
            : (author != null ? author.displayName() : null);
        List<ReactionDto> reactions = sm.reactions().entrySet().stream()
            .map(e -> new ReactionDto(e.getKey(), e.getValue())).toList();
        return new MessageDto(
            sm.id(), sm.conversationId(), sm.senderId(),
            senderName,
            sm.kind(), sm.text(), sm.mediaItems(), sm.poll(), sm.replyTo(),
            reactions, sm.createdAt(), sm.scheduledAt(), sm.clientId());
    }

    private static List<UUID> otherThan(List<UUID> all, UUID userId) {
        return all.stream().filter(id -> !id.equals(userId)).toList();
    }

    private static String snippet(StoredMessage m) {
        if (m.text() != null && !m.text().isBlank()) return m.text();
        return switch (m.kind()) {
            case "photo" -> "Photo";
            case "video" -> "Video";
            case "audio" -> "Audio message";
            case "sticker" -> "Sticker";
            case "location" -> "Location";
            case "poll" -> m.poll() != null ? m.poll().question() : "Poll";
            default -> "Attachment";
        };
    }

    /** Membership view for a brand-new conversation the recipient hasn't stored
     *  its own row for yet (fan-out only — their real row was written on create). */
    private static Membership syntheticMembership(ConversationMeta meta) {
        return new Membership(meta.id(), 1, false, false, null,
            meta.lastActivityAt(), meta.preview(), meta.title(), !"DIRECT".equals(meta.type()));
    }

    private static ResponseStatusException gone(UUID convId) {
        return new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
            "Membership missing for " + convId);
    }
}
