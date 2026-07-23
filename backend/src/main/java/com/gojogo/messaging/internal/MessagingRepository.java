package com.gojogo.messaging.internal;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.stereotype.Repository;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.Delete;
import software.amazon.awssdk.services.dynamodb.model.Put;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;
import software.amazon.awssdk.services.dynamodb.model.TransactWriteItem;
import software.amazon.awssdk.services.dynamodb.model.TransactWriteItemsRequest;
import software.amazon.awssdk.services.dynamodb.model.Update;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * Single-table DynamoDB access for the messaging module. Key design:
 *
 * <pre>
 *   Conversation meta   pk=CONV#{cid}       sk=META
 *   Direct-pair lookup  pk=DIRECT#{a}#{b}   sk=META            (a &lt; b lexically)
 *   Membership          pk=USER#{uid}       sk=CONV#{cid}      gsi1=USERCONV#{uid} / {lastActivity}
 *   Message             pk=CONV#{cid}       sk=MSG#{mid}       gsi1=CONVMSG#{cid}  / {createdAt}
 *   Connection (Lambda) pk=USER#{uid}       sk=CONN#{connId}
 * </pre>
 *
 * The two GSI1 partitions are namespaced (USERCONV# vs CONVMSG#) so one index
 * serves both "a user's conversations newest-first" and "a conversation's
 * messages in time order". Complex sub-objects (media, poll, reply) are stored
 * as JSON strings; reactions are a native map so a single tapback is a nested
 * update, not a read-modify-write of the whole message.
 */
@Repository
@EnableConfigurationProperties(MessagingProperties.class)
class MessagingRepository {

    private final DynamoDbClient db;
    private final ObjectMapper json;
    private final String table;

    MessagingRepository(DynamoDbClient db, ObjectMapper json, MessagingProperties props) {
        this.db = db;
        this.json = json;
        this.table = props.table();
    }

    // ---- keys -------------------------------------------------------------

    private static String directKey(UUID a, UUID b) {
        String x = a.toString(), y = b.toString();
        return "DIRECT#" + (x.compareTo(y) <= 0 ? x + "#" + y : y + "#" + x);
    }

    private static AttributeValue s(String v) { return AttributeValue.fromS(v); }
    private static AttributeValue n(long v) { return AttributeValue.fromN(Long.toString(v)); }
    private static AttributeValue bool(boolean v) { return AttributeValue.fromBool(v); }

    // ---- conversations ----------------------------------------------------

    record ConversationMeta(UUID id, String type, String title, List<UUID> participants,
                            UUID circleId, String background, UUID createdBy,
                            Instant createdAt, Instant lastActivityAt, String preview) {}

    record Membership(UUID conversationId, int unread, boolean pinned, boolean muted,
                      UUID lastReadMessageId, Instant lastActivityAt, String preview,
                      String title, boolean isGroup) {}

    /** Returns the existing direct conversation id for the pair, if any. */
    Optional<UUID> findDirectConversation(UUID a, UUID b) {
        var item = db.getItem(r -> r.tableName(table).key(Map.of(
            "pk", s(directKey(a, b)), "sk", s("META")))).item();
        if (item == null || item.isEmpty()) return Optional.empty();
        return Optional.of(UUID.fromString(item.get("convId").s()));
    }

    Optional<ConversationMeta> getConversation(UUID convId) {
        var item = db.getItem(r -> r.tableName(table).key(Map.of(
            "pk", s("CONV#" + convId), "sk", s("META")))).item();
        if (item == null || item.isEmpty()) return Optional.empty();
        return Optional.of(readMeta(item));
    }

    private ConversationMeta readMeta(Map<String, AttributeValue> it) {
        List<UUID> participants = it.getOrDefault("participants", AttributeValue.fromSs(List.of()))
            .ss().stream().map(UUID::fromString).toList();
        return new ConversationMeta(
            UUID.fromString(it.get("convId").s()),
            it.get("ctype").s(),
            attr(it, "title"),
            participants,
            it.containsKey("circleId") ? UUID.fromString(it.get("circleId").s()) : null,
            attr(it, "background"),
            it.containsKey("createdBy") ? UUID.fromString(it.get("createdBy").s()) : null,
            Instant.parse(it.get("createdAt").s()),
            Instant.parse(it.get("lastActivityAt").s()),
            attr(it, "preview"));
    }

    /** Creates the conversation meta + one membership row per participant (+ a
     *  direct-pair lookup for 1:1) in a single transaction. */
    void createConversation(ConversationMeta meta) {
        List<TransactWriteItem> writes = new ArrayList<>();

        Map<String, AttributeValue> metaItem = new HashMap<>();
        metaItem.put("pk", s("CONV#" + meta.id()));
        metaItem.put("sk", s("META"));
        metaItem.put("convId", s(meta.id().toString()));
        metaItem.put("ctype", s(meta.type()));
        putIfPresent(metaItem, "title", meta.title());
        putIfPresent(metaItem, "background", meta.background());
        if (!meta.participants().isEmpty()) {
            metaItem.put("participants", AttributeValue.fromSs(
                meta.participants().stream().map(UUID::toString).toList()));
        }
        if (meta.circleId() != null) metaItem.put("circleId", s(meta.circleId().toString()));
        if (meta.createdBy() != null) metaItem.put("createdBy", s(meta.createdBy().toString()));
        metaItem.put("createdAt", s(meta.createdAt().toString()));
        metaItem.put("lastActivityAt", s(meta.lastActivityAt().toString()));
        putIfPresent(metaItem, "preview", meta.preview());
        writes.add(TransactWriteItem.builder().put(Put.builder()
            .tableName(table).item(metaItem).build()).build());

        boolean isGroup = !"DIRECT".equals(meta.type());
        for (UUID uid : meta.participants()) {
            writes.add(TransactWriteItem.builder().put(Put.builder().tableName(table)
                .item(membershipItem(uid, meta.id(), 0, meta.lastActivityAt(),
                    meta.preview(), meta.title(), isGroup, false, false, null))
                .build()).build());
        }

        if ("DIRECT".equals(meta.type()) && meta.participants().size() == 2) {
            Map<String, AttributeValue> lookup = Map.of(
                "pk", s(directKey(meta.participants().get(0), meta.participants().get(1))),
                "sk", s("META"),
                "convId", s(meta.id().toString()));
            writes.add(TransactWriteItem.builder().put(Put.builder()
                .tableName(table).item(lookup).build()).build());
        }

        db.transactWriteItems(TransactWriteItemsRequest.builder()
            .transactItems(writes).build());
    }

    private Map<String, AttributeValue> membershipItem(
            UUID uid, UUID convId, int unread, Instant lastActivity, String preview,
            String title, boolean isGroup, boolean pinned, boolean muted, UUID lastReadMessageId) {
        Map<String, AttributeValue> m = new HashMap<>();
        m.put("pk", s("USER#" + uid));
        m.put("sk", s("CONV#" + convId));
        m.put("gsi1pk", s("USERCONV#" + uid));
        m.put("gsi1sk", s(lastActivity.toString()));
        m.put("convId", s(convId.toString()));
        m.put("unread", n(unread));
        m.put("pinned", bool(pinned));
        m.put("muted", bool(muted));
        m.put("isGroup", bool(isGroup));
        m.put("lastActivityAt", s(lastActivity.toString()));
        putIfPresent(m, "preview", preview);
        putIfPresent(m, "title", title);
        if (lastReadMessageId != null) m.put("lastReadMessageId", s(lastReadMessageId.toString()));
        return m;
    }

    List<Membership> listMemberships(UUID userId) {
        QueryResponse resp = db.query(QueryRequest.builder()
            .tableName(table).indexName("gsi1")
            .keyConditionExpression("gsi1pk = :p")
            .expressionAttributeValues(Map.of(":p", s("USERCONV#" + userId)))
            .scanIndexForward(false)
            .build());
        List<Membership> out = new ArrayList<>();
        for (var it : resp.items()) out.add(readMembership(it));
        return out;
    }

    Optional<Membership> getMembership(UUID userId, UUID convId) {
        var item = db.getItem(r -> r.tableName(table).key(Map.of(
            "pk", s("USER#" + userId), "sk", s("CONV#" + convId)))).item();
        if (item == null || item.isEmpty()) return Optional.empty();
        return Optional.of(readMembership(item));
    }

    private Membership readMembership(Map<String, AttributeValue> it) {
        return new Membership(
            UUID.fromString(it.get("convId").s()),
            it.containsKey("unread") ? Integer.parseInt(it.get("unread").n()) : 0,
            it.containsKey("pinned") && it.get("pinned").bool(),
            it.containsKey("muted") && it.get("muted").bool(),
            it.containsKey("lastReadMessageId") ? UUID.fromString(it.get("lastReadMessageId").s()) : null,
            Instant.parse(it.get("lastActivityAt").s()),
            attr(it, "preview"),
            attr(it, "title"),
            it.containsKey("isGroup") && it.get("isGroup").bool());
    }

    // ---- messages ---------------------------------------------------------

    record StoredMessage(UUID id, UUID conversationId, UUID senderId, String kind, String text,
                         List<MediaItemDto> mediaItems, PollDto poll, ReplySnippetDto replyTo,
                         Map<UUID, String> reactions, Instant createdAt, Instant scheduledAt,
                         UUID clientId) {}

    /** Appends a message and, in the same transaction, bumps every
     *  participant's membership (activity, preview, unread except the sender). */
    void appendMessage(StoredMessage msg, List<UUID> participants) {
        Map<String, AttributeValue> item = new HashMap<>();
        item.put("pk", s("CONV#" + msg.conversationId()));
        item.put("sk", s("MSG#" + msg.id()));
        item.put("gsi1pk", s("CONVMSG#" + msg.conversationId()));
        item.put("gsi1sk", s(msg.createdAt().toString()));
        item.put("msgId", s(msg.id().toString()));
        item.put("convId", s(msg.conversationId().toString()));
        item.put("senderId", s(msg.senderId().toString()));
        item.put("kind", s(msg.kind()));
        putIfPresent(item, "text", msg.text());
        putJson(item, "mediaJson", msg.mediaItems());
        putJson(item, "pollJson", msg.poll());
        putJson(item, "replyJson", msg.replyTo());
        item.put("reactions", AttributeValue.fromM(reactionsToAttr(msg.reactions())));
        item.put("createdAt", s(msg.createdAt().toString()));
        if (msg.scheduledAt() != null) item.put("scheduledAt", s(msg.scheduledAt().toString()));
        if (msg.clientId() != null) item.put("clientId", s(msg.clientId().toString()));

        List<TransactWriteItem> writes = new ArrayList<>();
        writes.add(TransactWriteItem.builder().put(Put.builder()
            .tableName(table).item(item).build()).build());

        String preview = msg.text() != null && !msg.text().isBlank()
            ? msg.text() : previewFor(msg.kind());
        for (UUID uid : participants) {
            boolean isSender = uid.equals(msg.senderId());
            Update.Builder u = Update.builder().tableName(table)
                .key(Map.of("pk", s("USER#" + uid), "sk", s("CONV#" + msg.conversationId())));
            if (isSender) {
                u.updateExpression("SET lastActivityAt = :t, gsi1sk = :t, preview = :p")
                    .expressionAttributeValues(Map.of(
                        ":t", s(msg.createdAt().toString()), ":p", s(preview)));
            } else {
                u.updateExpression("SET lastActivityAt = :t, gsi1sk = :t, preview = :p, "
                        + "unread = if_not_exists(unread, :zero) + :one")
                    .expressionAttributeValues(Map.of(
                        ":t", s(msg.createdAt().toString()), ":p", s(preview),
                        ":zero", n(0), ":one", n(1)));
            }
            writes.add(TransactWriteItem.builder().update(u.build()).build());
        }
        db.transactWriteItems(TransactWriteItemsRequest.builder().transactItems(writes).build());
    }

    Optional<StoredMessage> getMessage(UUID convId, UUID msgId) {
        var item = db.getItem(r -> r.tableName(table).key(Map.of(
            "pk", s("CONV#" + convId), "sk", s("MSG#" + msgId)))).item();
        if (item == null || item.isEmpty()) return Optional.empty();
        return Optional.of(readMessage(item));
    }

    /** Newest-first page of messages, older than {@code before} when supplied. */
    List<StoredMessage> listMessages(UUID convId, Instant before, int limit) {
        Map<String, AttributeValue> values = new HashMap<>();
        values.put(":p", s("CONVMSG#" + convId));
        String cond = "gsi1pk = :p";
        if (before != null) {
            cond += " AND gsi1sk < :b";
            values.put(":b", s(before.toString()));
        }
        QueryResponse resp = db.query(QueryRequest.builder()
            .tableName(table).indexName("gsi1")
            .keyConditionExpression(cond)
            .expressionAttributeValues(values)
            .scanIndexForward(false)
            .limit(limit)
            .build());
        List<StoredMessage> out = new ArrayList<>();
        for (var it : resp.items()) out.add(readMessage(it));
        return out;
    }

    private StoredMessage readMessage(Map<String, AttributeValue> it) {
        return new StoredMessage(
            UUID.fromString(it.get("msgId").s()),
            UUID.fromString(it.get("convId").s()),
            UUID.fromString(it.get("senderId").s()),
            it.get("kind").s(),
            attr(it, "text"),
            readJson(it, "mediaJson", new TypeReference<List<MediaItemDto>>() {}),
            readJson(it, "pollJson", new TypeReference<PollDto>() {}),
            readJson(it, "replyJson", new TypeReference<ReplySnippetDto>() {}),
            reactionsFromAttr(it.get("reactions")),
            Instant.parse(it.get("createdAt").s()),
            it.containsKey("scheduledAt") ? Instant.parse(it.get("scheduledAt").s()) : null,
            it.containsKey("clientId") ? UUID.fromString(it.get("clientId").s()) : null);
    }

    // ---- scheduled (send-later) -------------------------------------------

    // Pending scheduled messages live under a single partition keyed by due
    // time, so the delivery poller can scan the ones that are due. They are NOT
    // in the conversation until delivered, so recipients don't see them early.
    //   pk=SCHED#DUE   sk={scheduledAtIso}#{msgId}

    record ScheduledMessage(String scheduleKey, StoredMessage message) {}

    void putScheduledMessage(StoredMessage msg) {
        Map<String, AttributeValue> item = new HashMap<>();
        item.put("pk", s("SCHED#DUE"));
        item.put("sk", s(msg.scheduledAt() + "#" + msg.id()));
        item.put("msgId", s(msg.id().toString()));
        item.put("convId", s(msg.conversationId().toString()));
        item.put("senderId", s(msg.senderId().toString()));
        item.put("kind", s(msg.kind()));
        putIfPresent(item, "text", msg.text());
        putJson(item, "mediaJson", msg.mediaItems());
        putJson(item, "pollJson", msg.poll());
        putJson(item, "replyJson", msg.replyTo());
        item.put("createdAt", s(msg.scheduledAt().toString()));
        item.put("scheduledAt", s(msg.scheduledAt().toString()));
        if (msg.clientId() != null) item.put("clientId", s(msg.clientId().toString()));
        db.putItem(r -> r.tableName(table).item(item));
    }

    List<ScheduledMessage> listDueScheduled(Instant now, int limit) {
        QueryResponse resp = db.query(QueryRequest.builder()
            .tableName(table)
            .keyConditionExpression("pk = :p AND sk < :cutoff")
            .expressionAttributeValues(Map.of(
                // "~" sorts after any UUID char, so this includes every message
                // whose scheduled time is <= now (sk = "{iso}#{uuid}").
                ":p", s("SCHED#DUE"), ":cutoff", s(now + "#~")))
            .limit(limit)
            .build());
        List<ScheduledMessage> out = new ArrayList<>();
        for (var it : resp.items()) {
            out.add(new ScheduledMessage(it.get("sk").s(), readMessage(it)));
        }
        return out;
    }

    /** Atomically claims a due message (only one poller instance wins). */
    boolean claimScheduled(String scheduleKey) {
        try {
            db.deleteItem(r -> r.tableName(table)
                .key(Map.of("pk", s("SCHED#DUE"), "sk", s(scheduleKey)))
                .conditionExpression("attribute_exists(sk)"));
            return true;
        } catch (software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException e) {
            return false;
        }
    }

    // ---- reactions --------------------------------------------------------

    void setReaction(UUID convId, UUID msgId, UUID userId, String tapback) {
        db.updateItem(r -> r.tableName(table)
            .key(Map.of("pk", s("CONV#" + convId), "sk", s("MSG#" + msgId)))
            .updateExpression("SET reactions.#u = :t")
            .conditionExpression("attribute_exists(sk)")
            .expressionAttributeNames(Map.of("#u", userId.toString()))
            .expressionAttributeValues(Map.of(":t", s(tapback))));
    }

    void clearReaction(UUID convId, UUID msgId, UUID userId) {
        db.updateItem(r -> r.tableName(table)
            .key(Map.of("pk", s("CONV#" + convId), "sk", s("MSG#" + msgId)))
            .updateExpression("REMOVE reactions.#u")
            .expressionAttributeNames(Map.of("#u", userId.toString())));
    }

    /** Overwrites the stored poll after a vote is applied (read-modify-write). */
    void updatePoll(UUID convId, UUID msgId, PollDto poll) {
        db.updateItem(r -> r.tableName(table)
            .key(Map.of("pk", s("CONV#" + convId), "sk", s("MSG#" + msgId)))
            .updateExpression("SET pollJson = :p")
            .conditionExpression("attribute_exists(sk)")
            .expressionAttributeValues(Map.of(":p", s(writeJson(poll)))));
    }

    // ---- read state -------------------------------------------------------

    void markRead(UUID userId, UUID convId, UUID lastReadMessageId) {
        db.updateItem(r -> r.tableName(table)
            .key(Map.of("pk", s("USER#" + userId), "sk", s("CONV#" + convId)))
            .updateExpression("SET unread = :zero, lastReadMessageId = :m")
            .expressionAttributeValues(Map.of(
                ":zero", n(0), ":m", s(lastReadMessageId.toString()))));
    }

    void setPinned(UUID userId, UUID convId, boolean pinned) {
        db.updateItem(r -> r.tableName(table)
            .key(Map.of("pk", s("USER#" + userId), "sk", s("CONV#" + convId)))
            .updateExpression("SET pinned = :v")
            .expressionAttributeValues(Map.of(":v", bool(pinned))));
    }

    void deleteMembership(UUID userId, UUID convId) {
        db.deleteItem(r -> r.tableName(table)
            .key(Map.of("pk", s("USER#" + userId), "sk", s("CONV#" + convId))));
    }

    // ---- connection registry (written by the WS Lambdas) ------------------

    // The $connect Lambda only has the caller's Cognito subject from the JWT it
    // authorizes, not the app profile id — so connections are keyed by sub. The
    // Fanout bridges profile id -> sub via ProfileApi before calling this.

    /** Live WebSocket connection ids for a Cognito subject, for @connections fan-out. */
    List<String> connectionsForSub(String cognitoSub) {
        QueryResponse resp = db.query(QueryRequest.builder()
            .tableName(table)
            .keyConditionExpression("pk = :p AND begins_with(sk, :c)")
            .expressionAttributeValues(Map.of(
                ":p", s("SUB#" + cognitoSub), ":c", s("CONN#")))
            .build());
        List<String> ids = new ArrayList<>();
        for (var it : resp.items()) ids.add(it.get("connectionId").s());
        return ids;
    }

    void removeConnection(String cognitoSub, String connectionId) {
        db.deleteItem(r -> r.tableName(table)
            .key(Map.of("pk", s("SUB#" + cognitoSub), "sk", s("CONN#" + connectionId))));
    }

    // ---- World identity (WhatsApp-style: phone-verified messaging profile) --

    // Items:
    //   World profile   pk=WORLDUSER#{profileId}  sk=PROFILE
    //   Phone index      pk=WORLDPHONE#{e164}      sk=PROFILE   { profileId }
    //   OTP (one active) pk=WORLDOTP#{profileId}   sk=OTP       (+ ttl)

    record WorldProfile(UUID profileId, String phone, String displayName,
                        String avatarUrl, Instant verifiedAt, boolean setupComplete) {}

    record OtpRecord(String phone, String codeHash, Instant expiresAt, int attempts) {}

    Optional<WorldProfile> getWorldProfile(UUID profileId) {
        var item = db.getItem(r -> r.tableName(table).key(Map.of(
            "pk", s("WORLDUSER#" + profileId), "sk", s("PROFILE")))).item();
        if (item == null || item.isEmpty()) return Optional.empty();
        return Optional.of(readWorldProfile(item));
    }

    Map<UUID, WorldProfile> worldProfilesByIds(java.util.Collection<UUID> ids) {
        Map<UUID, WorldProfile> out = new LinkedHashMap<>();
        for (UUID id : new LinkedHashSet<>(ids)) {
            getWorldProfile(id).ifPresent(p -> out.put(id, p));
        }
        return out;
    }

    private WorldProfile readWorldProfile(Map<String, AttributeValue> it) {
        return new WorldProfile(
            UUID.fromString(it.get("profileId").s()),
            attr(it, "phone"),
            attr(it, "displayName"),
            attr(it, "avatarUrl"),
            it.containsKey("verifiedAt") ? Instant.parse(it.get("verifiedAt").s()) : null,
            it.containsKey("setupComplete") && it.get("setupComplete").bool());
    }

    void putWorldProfile(WorldProfile p) {
        Map<String, AttributeValue> item = new HashMap<>();
        item.put("pk", s("WORLDUSER#" + p.profileId()));
        item.put("sk", s("PROFILE"));
        item.put("profileId", s(p.profileId().toString()));
        putIfPresent(item, "phone", p.phone());
        putIfPresent(item, "displayName", p.displayName());
        putIfPresent(item, "avatarUrl", p.avatarUrl());
        if (p.verifiedAt() != null) item.put("verifiedAt", s(p.verifiedAt().toString()));
        item.put("setupComplete", bool(p.setupComplete()));
        db.putItem(r -> r.tableName(table).item(item));
    }

    void putPhoneIndex(String e164, UUID profileId) {
        db.putItem(r -> r.tableName(table).item(Map.of(
            "pk", s("WORLDPHONE#" + e164), "sk", s("PROFILE"),
            "profileId", s(profileId.toString()))));
    }

    Optional<UUID> profileIdForPhone(String e164) {
        var item = db.getItem(r -> r.tableName(table).key(Map.of(
            "pk", s("WORLDPHONE#" + e164), "sk", s("PROFILE")))).item();
        if (item == null || item.isEmpty()) return Optional.empty();
        return Optional.of(UUID.fromString(item.get("profileId").s()));
    }

    void putOtp(UUID profileId, String phone, String codeHash, Instant expiresAt, int attempts) {
        Map<String, AttributeValue> item = new HashMap<>();
        item.put("pk", s("WORLDOTP#" + profileId));
        item.put("sk", s("OTP"));
        item.put("phone", s(phone));
        item.put("codeHash", s(codeHash));
        item.put("expiresAt", s(expiresAt.toString()));
        item.put("attempts", n(attempts));
        item.put("ttl", n(expiresAt.getEpochSecond() + 300)); // sweep 5 min after expiry
        db.putItem(r -> r.tableName(table).item(item));
    }

    Optional<OtpRecord> getOtp(UUID profileId) {
        var item = db.getItem(r -> r.tableName(table).key(Map.of(
            "pk", s("WORLDOTP#" + profileId), "sk", s("OTP")))).item();
        if (item == null || item.isEmpty()) return Optional.empty();
        return Optional.of(new OtpRecord(
            item.get("phone").s(), item.get("codeHash").s(),
            Instant.parse(item.get("expiresAt").s()),
            item.containsKey("attempts") ? Integer.parseInt(item.get("attempts").n()) : 0));
    }

    void deleteOtp(UUID profileId) {
        db.deleteItem(r -> r.tableName(table)
            .key(Map.of("pk", s("WORLDOTP#" + profileId), "sk", s("OTP"))));
    }

    // ---- json / attr helpers ---------------------------------------------

    private static String attr(Map<String, AttributeValue> it, String k) {
        AttributeValue v = it.get(k);
        return v == null ? null : v.s();
    }

    private static void putIfPresent(Map<String, AttributeValue> m, String k, String v) {
        if (v != null && !v.isBlank()) m.put(k, s(v));
    }

    private void putJson(Map<String, AttributeValue> m, String k, Object value) {
        if (value == null) return;
        if (value instanceof List<?> l && l.isEmpty()) return;
        m.put(k, s(writeJson(value)));
    }

    private String writeJson(Object value) {
        try {
            return json.writeValueAsString(value);
        } catch (Exception e) {
            throw new IllegalStateException("messaging json write failed", e);
        }
    }

    private <T> T readJson(Map<String, AttributeValue> it, String k, TypeReference<T> type) {
        AttributeValue v = it.get(k);
        if (v == null || v.s() == null) return null;
        try {
            return json.readValue(v.s(), type);
        } catch (Exception e) {
            throw new IllegalStateException("messaging json read failed for " + k, e);
        }
    }

    private static Map<String, AttributeValue> reactionsToAttr(Map<UUID, String> reactions) {
        Map<String, AttributeValue> m = new LinkedHashMap<>();
        if (reactions != null) reactions.forEach((k, v) -> m.put(k.toString(), s(v)));
        return m;
    }

    private static Map<UUID, String> reactionsFromAttr(AttributeValue v) {
        Map<UUID, String> out = new LinkedHashMap<>();
        if (v != null && v.hasM()) {
            v.m().forEach((k, val) -> out.put(UUID.fromString(k), val.s()));
        }
        return out;
    }

    private static String previewFor(String kind) {
        return switch (kind) {
            case "photo" -> "📷 Photo";
            case "video" -> "📹 Video";
            case "carousel" -> "🖼 Attachments";
            case "audio" -> "🎤 Audio message";
            case "location" -> "📍 Location";
            case "file" -> "📄 Attachment";
            case "poll" -> "📊 Poll";
            default -> "Message";
        };
    }
}
