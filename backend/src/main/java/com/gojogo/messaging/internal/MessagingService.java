package com.gojogo.messaging.internal;

import com.gojogo.messaging.internal.MessagingRepository.ConversationMeta;
import com.gojogo.messaging.internal.MessagingRepository.Membership;
import com.gojogo.messaging.internal.MessagingRepository.StoredMessage;
import com.gojogo.messaging.internal.MessagingRepository.WorldProfile;
import com.gojogo.media.MediaApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
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

    MessagingService(MessagingRepository repo, ProfileApi profiles, Fanout fanout, MediaApi media) {
        this.repo = repo;
        this.profiles = profiles;
        this.fanout = fanout;
        this.media = media;
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
        Set<UUID> participants = new LinkedHashSet<>(req.participantIds());
        participants.add(userId);
        if (participants.size() < 2) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "A conversation needs at least one other participant");
        }
        List<UUID> ordered = new ArrayList<>(participants);
        boolean isDirect = ordered.size() == 2 && req.circleId() == null;

        if (isDirect) {
            Optional<UUID> existing = repo.findDirectConversation(ordered.get(0), ordered.get(1));
            if (existing.isPresent()) {
                ConversationMeta meta = repo.getConversation(existing.get()).orElseThrow();
                Membership m = repo.getMembership(userId, existing.get())
                    .orElseThrow(() -> gone(existing.get()));
                return toConversationDto(meta, m);
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
            null);
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
        requireParticipant(userId, convId);
        int capped = Math.min(Math.max(limit, 1), 50);
        List<StoredMessage> stored = repo.listMessages(convId, before, capped);
        List<UUID> senderIds = stored.stream().map(StoredMessage::senderId).toList();
        Map<UUID, ProfileDto> authors = profiles.findByIds(senderIds);
        Map<UUID, WorldProfile> worlds = repo.worldProfilesByIds(senderIds);
        List<MessageDto> messages = stored.stream().map(sm -> toMessageDto(sm, authors, worlds)).toList();
        Instant nextBefore = stored.size() == capped && !stored.isEmpty()
            ? stored.get(stored.size() - 1).createdAt() : null;
        return new MessagesResponse(messages, nextBefore);
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
        return dto;
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
            m.preview(), m.lastActivityAt(), m.unread(), m.pinned(), m.muted());
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
