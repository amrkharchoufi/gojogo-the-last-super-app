package com.gojogo.messaging.internal;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.gojogo.messaging.ConversationContext;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Repository;
import org.springframework.web.server.ResponseStatusException;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.Delete;
import software.amazon.awssdk.services.dynamodb.model.Put;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;
import software.amazon.awssdk.services.dynamodb.model.ScanRequest;
import software.amazon.awssdk.services.dynamodb.model.ScanResponse;
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
 *
 * <p>The client is built on the first call, not at startup: {@code create()}
 * resolves the region eagerly and throws when there isn't one, which would turn
 * "messaging isn't configured here" into "the application does not start". With
 * no table configured no client is ever built and every call fails with a 503,
 * the same shape as an unconfigured Sumsub or APNs.
 */
@Repository
@EnableConfigurationProperties(MessagingProperties.class)
class MessagingRepository {

    private static final Logger log = LoggerFactory.getLogger(MessagingRepository.class);

    private final ObjectMapper json;
    private final MessagingProperties props;
    private final String table;
    private volatile DynamoDbClient db;

    MessagingRepository(ObjectMapper json, MessagingProperties props) {
        this.json = json;
        this.props = props;
        this.table = props.table();
        if (!props.enabled()) {
            log.info("Messaging is off (no MESSAGING_TABLE) — conversations, My World and "
                + "send-later are unavailable on this environment; nothing else depends on them");
        } else {
            log.info("Messaging on: table '{}', WebSocket fan-out {}", table,
                props.fanoutEnabled() ? "on" : "OFF (writes land, nothing is pushed)");
        }
    }

    /** The DynamoDB client, built on first use. */
    private synchronized DynamoDbClient db() {
        if (!props.enabled()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Messaging isn't configured on this environment");
        }
        if (db == null) {
            db = DynamoDbClient.create();
        }
        return db;
    }

    @PreDestroy
    void close() {
        if (db != null) {
            db.close();
        }
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
                            Instant createdAt, Instant lastActivityAt, String preview,
                            ConversationContext context) {}

    record Membership(UUID conversationId, int unread, boolean pinned, boolean muted,
                      UUID lastReadMessageId, Instant lastActivityAt, String preview,
                      String title, boolean isGroup) {}

    /** Returns the existing direct conversation id for the pair, if any. */
    Optional<UUID> findDirectConversation(UUID a, UUID b) {
        var item = db().getItem(r -> r.tableName(table).key(Map.of(
            "pk", s(directKey(a, b)), "sk", s("META")))).item();
        if (item == null || item.isEmpty()) return Optional.empty();
        return Optional.of(UUID.fromString(item.get("convId").s()));
    }

    Optional<ConversationMeta> getConversation(UUID convId) {
        var item = db().getItem(r -> r.tableName(table).key(Map.of(
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
            attr(it, "preview"),
            readJson(it, "contextJson", new TypeReference<ConversationContext>() {}));
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
        putJson(metaItem, "contextJson", meta.context());
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

        db().transactWriteItems(TransactWriteItemsRequest.builder()
            .transactItems(writes).build());
    }

    /** Overwrites the reference card on an existing conversation (the reuse path:
     *  a buyer re-opens a thread from a different listing). */
    void updateContext(UUID convId, ConversationContext context) {
        db().updateItem(r -> r.tableName(table)
            .key(Map.of("pk", s("CONV#" + convId), "sk", s("META")))
            .updateExpression("SET contextJson = :c")
            .conditionExpression("attribute_exists(sk)")
            .expressionAttributeValues(Map.of(":c", s(writeJson(context)))));
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
        QueryResponse resp = db().query(QueryRequest.builder()
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
        var item = db().getItem(r -> r.tableName(table).key(Map.of(
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
            // `convId` and `gsi1pk` are re-stated on every bump, not just written
            // at create time: an update on a membership row that was deleted (the
            // participant left) recreates it, and a row without them is unreadable
            // and invisible to the list query — the thread would silently swallow
            // messages instead of coming back.
            if (isSender) {
                u.updateExpression("SET lastActivityAt = :t, gsi1sk = :t, preview = :p, "
                        + "convId = :cid, gsi1pk = :gpk")
                    .expressionAttributeValues(Map.of(
                        ":t", s(msg.createdAt().toString()), ":p", s(preview),
                        ":cid", s(msg.conversationId().toString()),
                        ":gpk", s("USERCONV#" + uid)));
            } else {
                u.updateExpression("SET lastActivityAt = :t, gsi1sk = :t, preview = :p, "
                        + "convId = :cid, gsi1pk = :gpk, "
                        + "unread = if_not_exists(unread, :zero) + :one")
                    .expressionAttributeValues(Map.of(
                        ":t", s(msg.createdAt().toString()), ":p", s(preview),
                        ":cid", s(msg.conversationId().toString()),
                        ":gpk", s("USERCONV#" + uid),
                        ":zero", n(0), ":one", n(1)));
            }
            writes.add(TransactWriteItem.builder().update(u.build()).build());
        }
        db().transactWriteItems(TransactWriteItemsRequest.builder().transactItems(writes).build());
    }

    Optional<StoredMessage> getMessage(UUID convId, UUID msgId) {
        var item = db().getItem(r -> r.tableName(table).key(Map.of(
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
        QueryResponse resp = db().query(QueryRequest.builder()
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
        db().putItem(r -> r.tableName(table).item(item));
    }

    List<ScheduledMessage> listDueScheduled(Instant now, int limit) {
        QueryResponse resp = db().query(QueryRequest.builder()
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
            db().deleteItem(r -> r.tableName(table)
                .key(Map.of("pk", s("SCHED#DUE"), "sk", s(scheduleKey)))
                .conditionExpression("attribute_exists(sk)"));
            return true;
        } catch (software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException e) {
            return false;
        }
    }

    // ---- reactions --------------------------------------------------------

    void setReaction(UUID convId, UUID msgId, UUID userId, String tapback) {
        db().updateItem(r -> r.tableName(table)
            .key(Map.of("pk", s("CONV#" + convId), "sk", s("MSG#" + msgId)))
            .updateExpression("SET reactions.#u = :t")
            .conditionExpression("attribute_exists(sk)")
            .expressionAttributeNames(Map.of("#u", userId.toString()))
            .expressionAttributeValues(Map.of(":t", s(tapback))));
    }

    void clearReaction(UUID convId, UUID msgId, UUID userId) {
        db().updateItem(r -> r.tableName(table)
            .key(Map.of("pk", s("CONV#" + convId), "sk", s("MSG#" + msgId)))
            .updateExpression("REMOVE reactions.#u")
            .expressionAttributeNames(Map.of("#u", userId.toString())));
    }

    /** Overwrites the stored poll after a vote is applied (read-modify-write). */
    void updatePoll(UUID convId, UUID msgId, PollDto poll) {
        db().updateItem(r -> r.tableName(table)
            .key(Map.of("pk", s("CONV#" + convId), "sk", s("MSG#" + msgId)))
            .updateExpression("SET pollJson = :p")
            .conditionExpression("attribute_exists(sk)")
            .expressionAttributeValues(Map.of(":p", s(writeJson(poll)))));
    }

    // ---- read state -------------------------------------------------------

    void markRead(UUID userId, UUID convId, UUID lastReadMessageId) {
        db().updateItem(r -> r.tableName(table)
            .key(Map.of("pk", s("USER#" + userId), "sk", s("CONV#" + convId)))
            .updateExpression("SET unread = :zero, lastReadMessageId = :m")
            .expressionAttributeValues(Map.of(
                ":zero", n(0), ":m", s(lastReadMessageId.toString()))));
    }

    void setPinned(UUID userId, UUID convId, boolean pinned) {
        db().updateItem(r -> r.tableName(table)
            .key(Map.of("pk", s("USER#" + userId), "sk", s("CONV#" + convId)))
            .updateExpression("SET pinned = :v")
            .expressionAttributeValues(Map.of(":v", bool(pinned))));
    }

    void deleteMembership(UUID userId, UUID convId) {
        db().deleteItem(r -> r.tableName(table)
            .key(Map.of("pk", s("USER#" + userId), "sk", s("CONV#" + convId))));
    }

    /** Re-creates the membership row of a participant who left, so the thread is
     *  back in their list (read from the start, since their unread was dropped). */
    Membership rejoin(UUID userId, ConversationMeta meta) {
        Map<String, AttributeValue> item = membershipItem(
            userId, meta.id(), 0, meta.lastActivityAt(), meta.preview(), meta.title(),
            !"DIRECT".equals(meta.type()), false, false, null);
        db().putItem(r -> r.tableName(table).item(item));
        return readMembership(item);
    }

    // ---- connection registry (written by the WS Lambdas) ------------------

    // The $connect Lambda only has the caller's Cognito subject from the JWT it
    // authorizes, not the app profile id — so connections are keyed by sub. The
    // Fanout bridges profile id -> sub via ProfileApi before calling this.

    /** Live WebSocket connection ids for a Cognito subject, for @connections fan-out. */
    List<String> connectionsForSub(String cognitoSub) {
        QueryResponse resp = db().query(QueryRequest.builder()
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
        db().deleteItem(r -> r.tableName(table)
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
        var item = db().getItem(r -> r.tableName(table).key(Map.of(
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
        db().putItem(r -> r.tableName(table).item(item));
    }

    void putPhoneIndex(String e164, UUID profileId) {
        db().putItem(r -> r.tableName(table).item(Map.of(
            "pk", s("WORLDPHONE#" + e164), "sk", s("PROFILE"),
            "profileId", s(profileId.toString()))));
    }

    Optional<UUID> profileIdForPhone(String e164) {
        var item = db().getItem(r -> r.tableName(table).key(Map.of(
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
        db().putItem(r -> r.tableName(table).item(item));
    }

    Optional<OtpRecord> getOtp(UUID profileId) {
        var item = db().getItem(r -> r.tableName(table).key(Map.of(
            "pk", s("WORLDOTP#" + profileId), "sk", s("OTP")))).item();
        if (item == null || item.isEmpty()) return Optional.empty();
        return Optional.of(new OtpRecord(
            item.get("phone").s(), item.get("codeHash").s(),
            Instant.parse(item.get("expiresAt").s()),
            item.containsKey("attempts") ? Integer.parseInt(item.get("attempts").n()) : 0));
    }

    void deleteOtp(UUID profileId) {
        db().deleteItem(r -> r.tableName(table)
            .key(Map.of("pk", s("WORLDOTP#" + profileId), "sk", s("OTP"))));
    }

    // ---- contact aliases (private per-viewer renames) ----------------------

    // Item: pk=WORLDUSER#{viewerId}  sk=ALIAS#{contactId}  { alias }
    //
    // Deliberately in the viewer's own partition, next to their WORLDUSER#/PROFILE
    // item: an alias is a property of the *edge* from the viewer to the contact,
    // never of the contact. It is the viewer's data, so it is stored under the
    // viewer's key, read with one query on their partition, and is unreachable
    // from the renamed person's own reads by construction rather than by a filter.

    /** Every rename this viewer has made, contactId -> alias. One query. */
    Map<UUID, String> aliasesFor(UUID viewerId) {
        Map<UUID, String> out = new HashMap<>();
        QueryResponse resp = db().query(QueryRequest.builder()
            .tableName(table)
            .keyConditionExpression("pk = :p AND begins_with(sk, :a)")
            .expressionAttributeValues(Map.of(
                ":p", s("WORLDUSER#" + viewerId), ":a", s("ALIAS#")))
            .build());
        for (var it : resp.items()) {
            String alias = attr(it, "alias");
            if (alias == null) continue;
            out.put(UUID.fromString(it.get("sk").s().substring("ALIAS#".length())), alias);
        }
        return out;
    }

    /** One viewer's rename of one contact. Used on the push path, where the
     *  whole map would be wasted work. */
    Optional<String> getAlias(UUID viewerId, UUID contactId) {
        var item = db().getItem(r -> r.tableName(table).key(Map.of(
            "pk", s("WORLDUSER#" + viewerId), "sk", s("ALIAS#" + contactId)))).item();
        if (item == null || item.isEmpty()) return Optional.empty();
        return Optional.ofNullable(attr(item, "alias"));
    }

    void putAlias(UUID viewerId, UUID contactId, String alias) {
        db().putItem(r -> r.tableName(table).item(Map.of(
            "pk", s("WORLDUSER#" + viewerId),
            "sk", s("ALIAS#" + contactId),
            "contactId", s(contactId.toString()),
            "alias", s(alias))));
    }

    void deleteAlias(UUID viewerId, UUID contactId) {
        db().deleteItem(r -> r.tableName(table).key(Map.of(
            "pk", s("WORLDUSER#" + viewerId), "sk", s("ALIAS#" + contactId))));
    }

    // ---- contacts, circles, content (the GojoMessages graph) ---------------

    // Items:
    //   Contact        pk=WORLDUSER#{ownerId}    sk=CONTACT#{contactId}
    //   Reverse edge   pk=CONTACTOF#{contactId}  sk=OWNER#{ownerId}
    //   Circle         pk=WORLDUSER#{ownerId}    sk=CIRCLE#{circleId}
    //   Author's copy  pk=WORLDPOST#{authorId}   sk={POST|STORY}#{ts}#{id}
    //   Feed copy      pk=WORLDFEED#{viewerId}   sk={POST|STORY}#{ts}#{id}
    //
    // The reverse edge is what makes "everyone who has my number" answerable: a
    // contact list reads one way, and an audience reads the other. Both are
    // written in one transaction so the two directions cannot disagree.
    //
    // Content is fanned out on write, one feed copy per audience member. That is
    // deliberate: a feed read touches only the reader's own partition, so there
    // is no audience filter on the read path that could ever be forgotten. The
    // cost is writes proportional to audience size, which is the right trade for
    // a network whose whole premise is the few hundred people you actually know.

    record ContactEdge(UUID contactId, String alias, Instant addedAt) {}

    record Circle(UUID id, String name, String colorHex, List<UUID> memberIds, Instant createdAt) {}

    /**
     * @param viewers who this was actually fanned out to, recorded on the
     *                author's copy at publish time. Deleting re-reads this rather
     *                than re-resolving the audience: a contact dropped or a
     *                circle edited after publishing would make a re-resolved
     *                audience miss the copies it needs to remove, leaving the
     *                post alive in a feed the author can no longer reach.
     *                Null on feed copies, which never carry it.
     */
    record StoredContent(UUID id, UUID authorId, String kind, String text,
                         List<MediaItemDto> mediaItems, Instant createdAt, Instant expiresAt,
                         String audience, List<UUID> circleIds, List<UUID> viewers) {

        boolean isStory() { return "story".equals(kind); }
    }

    /** Sort-key prefix. Stories and posts share a partition but never a query. */
    private static String contentPrefix(String kind) {
        return "story".equals(kind) ? "STORY#" : "POST#";
    }

    private static String contentSk(StoredContent c) {
        return contentPrefix(c.kind()) + c.createdAt() + "#" + c.id();
    }

    // ---- contacts ---------------------------------------------------------

    void addContact(UUID ownerId, UUID contactId, String phone) {
        Instant now = Instant.now();
        Map<String, AttributeValue> edge = new HashMap<>();
        edge.put("pk", s("WORLDUSER#" + ownerId));
        edge.put("sk", s("CONTACT#" + contactId));
        edge.put("contactId", s(contactId.toString()));
        putIfPresent(edge, "phone", phone);
        edge.put("addedAt", s(now.toString()));

        Map<String, AttributeValue> reverse = Map.of(
            "pk", s("CONTACTOF#" + contactId),
            "sk", s("OWNER#" + ownerId),
            "ownerId", s(ownerId.toString()),
            "addedAt", s(now.toString()));

        db().transactWriteItems(TransactWriteItemsRequest.builder().transactItems(
            TransactWriteItem.builder().put(Put.builder().tableName(table).item(edge).build()).build(),
            TransactWriteItem.builder().put(Put.builder().tableName(table).item(reverse).build()).build()
        ).build());
    }

    void removeContact(UUID ownerId, UUID contactId) {
        db().transactWriteItems(TransactWriteItemsRequest.builder().transactItems(
            TransactWriteItem.builder().delete(Delete.builder().tableName(table).key(Map.of(
                "pk", s("WORLDUSER#" + ownerId), "sk", s("CONTACT#" + contactId))).build()).build(),
            TransactWriteItem.builder().delete(Delete.builder().tableName(table).key(Map.of(
                "pk", s("CONTACTOF#" + contactId), "sk", s("OWNER#" + ownerId))).build()).build()
        ).build());
    }

    List<ContactEdge> listContacts(UUID ownerId) {
        Map<UUID, String> aliases = aliasesFor(ownerId);
        List<ContactEdge> out = new ArrayList<>();
        for (var it : queryPrefix("WORLDUSER#" + ownerId, "CONTACT#")) {
            UUID id = UUID.fromString(it.get("contactId").s());
            out.add(new ContactEdge(id, aliases.get(id),
                it.containsKey("addedAt") ? Instant.parse(it.get("addedAt").s()) : null));
        }
        return out;
    }

    boolean isContact(UUID ownerId, UUID contactId) {
        var item = db().getItem(r -> r.tableName(table).key(Map.of(
            "pk", s("WORLDUSER#" + ownerId), "sk", s("CONTACT#" + contactId)))).item();
        return item != null && !item.isEmpty();
    }

    /**
     * Everyone who has this person as a contact.
     *
     * <p>No longer the {@code CONTACTS} audience — that is the author's own
     * contact list now, since an audience made of people who added you is one
     * you cannot close. This still answers "who holds my number", which is what
     * decides whether somebody may be shown a number and added back.
     */
    List<UUID> followersOf(UUID contactId) {
        List<UUID> out = new ArrayList<>();
        for (var it : queryPrefix("CONTACTOF#" + contactId, "OWNER#")) {
            out.add(UUID.fromString(it.get("ownerId").s()));
        }
        return out;
    }

    // ---- circles ----------------------------------------------------------

    void putCircle(UUID ownerId, Circle circle) {
        Map<String, AttributeValue> item = new HashMap<>();
        item.put("pk", s("WORLDUSER#" + ownerId));
        item.put("sk", s("CIRCLE#" + circle.id()));
        item.put("circleId", s(circle.id().toString()));
        item.put("name", s(circle.name()));
        putIfPresent(item, "colorHex", circle.colorHex());
        putJson(item, "memberJson", circle.memberIds());
        item.put("createdAt", s(circle.createdAt().toString()));
        db().putItem(r -> r.tableName(table).item(item));
    }

    void deleteCircle(UUID ownerId, UUID circleId) {
        db().deleteItem(r -> r.tableName(table).key(Map.of(
            "pk", s("WORLDUSER#" + ownerId), "sk", s("CIRCLE#" + circleId))));
    }

    Optional<Circle> getCircle(UUID ownerId, UUID circleId) {
        var item = db().getItem(r -> r.tableName(table).key(Map.of(
            "pk", s("WORLDUSER#" + ownerId), "sk", s("CIRCLE#" + circleId)))).item();
        if (item == null || item.isEmpty()) return Optional.empty();
        return Optional.of(readCircle(item));
    }

    List<Circle> listCircles(UUID ownerId) {
        List<Circle> out = new ArrayList<>();
        for (var it : queryPrefix("WORLDUSER#" + ownerId, "CIRCLE#")) out.add(readCircle(it));
        return out;
    }

    private Circle readCircle(Map<String, AttributeValue> it) {
        List<UUID> members = readJson(it, "memberJson", new TypeReference<List<UUID>>() {});
        return new Circle(
            UUID.fromString(it.get("circleId").s()),
            attr(it, "name"),
            attr(it, "colorHex"),
            members == null ? List.of() : members,
            it.containsKey("createdAt") ? Instant.parse(it.get("createdAt").s()) : Instant.EPOCH);
    }

    // ---- content ----------------------------------------------------------

    /** Writes the author's copy plus one feed copy per viewer. */
    void publishContent(StoredContent content, List<UUID> viewers) {
        db().putItem(r -> r.tableName(table).item(contentItem(
            "WORLDPOST#" + content.authorId(), contentSk(content), content, true)));
        for (UUID viewer : viewers) {
            if (viewer.equals(content.authorId())) continue;
            db().putItem(r -> r.tableName(table).item(contentItem(
                "WORLDFEED#" + viewer, contentSk(content), content, false)));
        }
    }

    private Map<String, AttributeValue> contentItem(String pk, String sk, StoredContent c,
                                                    boolean authorCopy) {
        Map<String, AttributeValue> item = new HashMap<>();
        item.put("pk", s(pk));
        item.put("sk", s(sk));
        item.put("contentId", s(c.id().toString()));
        item.put("authorId", s(c.authorId().toString()));
        item.put("kind", s(c.kind()));
        putIfPresent(item, "text", c.text());
        putJson(item, "mediaJson", c.mediaItems());
        item.put("createdAt", s(c.createdAt().toString()));
        if (c.expiresAt() != null) {
            item.put("expiresAt", s(c.expiresAt().toString()));
            // DynamoDB sweeps the row itself; reads also filter, because TTL
            // deletion is eventual and a story must vanish on time regardless.
            item.put("ttl", n(c.expiresAt().getEpochSecond()));
        }
        // The audience the author picked is theirs to know. It rides on the
        // author's copy so it can be shown back to them, and is left off every
        // feed copy so a reader can't infer which circle they were put in. The
        // fanned-out viewer list rides there too, so a delete can find exactly
        // the copies this post created rather than guessing from today's graph.
        if (authorCopy) {
            putIfPresent(item, "audience", c.audience());
            putJson(item, "circleJson", c.circleIds());
            putJson(item, "viewerJson", c.viewers());
        }
        return item;
    }

    private StoredContent readContent(Map<String, AttributeValue> it) {
        List<MediaItemDto> media = readJson(it, "mediaJson", new TypeReference<List<MediaItemDto>>() {});
        List<UUID> circles = readJson(it, "circleJson", new TypeReference<List<UUID>>() {});
        List<UUID> viewers = readJson(it, "viewerJson", new TypeReference<List<UUID>>() {});
        return new StoredContent(
            UUID.fromString(it.get("contentId").s()),
            UUID.fromString(it.get("authorId").s()),
            attr(it, "kind"),
            attr(it, "text"),
            media == null ? List.of() : media,
            Instant.parse(it.get("createdAt").s()),
            it.containsKey("expiresAt") ? Instant.parse(it.get("expiresAt").s()) : null,
            attr(it, "audience"),
            circles == null ? List.of() : circles,
            viewers == null ? List.of() : viewers);
    }

    /** A reader's own feed partition. Nothing else is ever consulted. */
    List<StoredContent> feed(UUID viewerId, String kind, int limit) {
        return readContentPage("WORLDFEED#" + viewerId, contentPrefix(kind), limit);
    }

    /** One author's own copies — for their grid and the contact page tab. */
    List<StoredContent> contentBy(UUID authorId, String kind, int limit) {
        return readContentPage("WORLDPOST#" + authorId, contentPrefix(kind), limit);
    }

    private List<StoredContent> readContentPage(String pk, String prefix, int limit) {
        QueryResponse resp = db().query(QueryRequest.builder()
            .tableName(table)
            .keyConditionExpression("pk = :p AND begins_with(sk, :s)")
            .expressionAttributeValues(Map.of(":p", s(pk), ":s", s(prefix)))
            .scanIndexForward(false) // newest first
            .limit(Math.max(1, limit))
            .build());
        Instant now = Instant.now();
        List<StoredContent> out = new ArrayList<>();
        for (var it : resp.items()) {
            StoredContent c = readContent(it);
            // TTL deletion is eventual — never serve an expired story because
            // DynamoDB hasn't got round to sweeping it yet.
            if (c.expiresAt() != null && c.expiresAt().isBefore(now)) continue;
            out.add(c);
        }
        return out;
    }

    Optional<StoredContent> getContent(UUID authorId, UUID contentId) {
        for (String kind : List.of("post", "story")) {
            for (var it : queryPrefix("WORLDPOST#" + authorId, contentPrefix(kind))) {
                if (contentId.toString().equals(attr(it, "contentId"))) {
                    return Optional.of(readContent(it));
                }
            }
        }
        return Optional.empty();
    }

    /**
     * How much history a new contact is handed. Bounds the write burst on an
     * add, and is well past what anybody scrolls back to on a first look.
     */
    private static final int BACKLOG = 100;

    /**
     * Hands a newly admitted contact everything the author had <em>already</em>
     * published to their contacts.
     *
     * <p>Fan-out happens on write, so an add on its own only ever delivers the
     * author's <em>next</em> post: somebody let into an audience would find it
     * empty and stay that way until the author posted again. History is not a
     * different kind of content from what arrives a minute later, and admitting
     * somebody is a decision about them, not about a timestamp.
     *
     * <p>The new viewer is recorded on the author's copy as each one goes out,
     * because that stored list is what a delete walks — a copy handed out here
     * and not recorded there would outlive the post it came from.
     *
     * <p>Circle posts are deliberately left behind. A circle is a smaller
     * audience the author picked by hand, and being let into the contacts is not
     * being picked for one.
     */
    void deliverBacklog(UUID viewerId, UUID authorId) {
        for (String kind : List.of("post", "story")) {
            for (StoredContent c : readContentPage("WORLDPOST#" + authorId, contentPrefix(kind), BACKLOG)) {
                if (!WorldAudience.CONTACTS.name().equals(c.audience())) continue;
                if (c.viewers().contains(viewerId)) continue;
                db().putItem(r -> r.tableName(table).item(
                    contentItem("WORLDFEED#" + viewerId, contentSk(c), c, false)));
                List<UUID> viewers = new ArrayList<>(c.viewers());
                viewers.add(viewerId);
                recordViewers(c, viewers);
            }
        }
    }

    /**
     * The inverse: takes back what {@link #deliverBacklog} handed out, when the
     * contact is dropped. Only the contacts-audience copies — a post the author
     * sent a named circle was addressed to this person by hand, and dropping
     * them from the contacts is not the author unsaying that.
     */
    void withdrawBacklog(UUID viewerId, UUID authorId) {
        for (String kind : List.of("post", "story")) {
            for (StoredContent c : readContentPage("WORLDPOST#" + authorId, contentPrefix(kind), BACKLOG)) {
                if (!WorldAudience.CONTACTS.name().equals(c.audience())) continue;
                if (!c.viewers().contains(viewerId)) continue;
                db().deleteItem(r -> r.tableName(table).key(Map.of(
                    "pk", s("WORLDFEED#" + viewerId), "sk", s(contentSk(c)))));
                recordViewers(c, c.viewers().stream().filter(v -> !v.equals(viewerId)).toList());
            }
        }
    }

    /** Rewrites who a post was fanned out to, on the author's copy. */
    void recordViewers(StoredContent c, List<UUID> viewers) {
        String viewerJson = writeJson(viewers);
        db().updateItem(r -> r.tableName(table)
            .key(Map.of("pk", s("WORLDPOST#" + c.authorId()), "sk", s(contentSk(c))))
            .updateExpression("SET viewerJson = :v")
            .expressionAttributeValues(Map.of(":v", s(viewerJson))));
    }

    // ---- one-off reconciliation (see WorldAudienceReconciler) --------------

    /** Every author's own copy of everything they ever published. */
    List<StoredContent> scanAllAuthorContent() {
        List<StoredContent> out = new ArrayList<>();
        Map<String, AttributeValue> start = null;
        do {
            ScanRequest.Builder q = ScanRequest.builder()
                .tableName(table)
                .filterExpression("begins_with(pk, :p)")
                .expressionAttributeValues(Map.of(":p", s("WORLDPOST#")));
            if (start != null && !start.isEmpty()) q.exclusiveStartKey(start);
            ScanResponse resp = db().scan(q.build());
            for (var it : resp.items()) out.add(readContent(it));
            start = resp.lastEvaluatedKey();
        } while (start != null && !start.isEmpty());
        return out;
    }

    /** One reader's copy of one post — the unit this whole model is made of. */
    void putFeedCopy(UUID viewerId, StoredContent c) {
        db().putItem(r -> r.tableName(table).item(
            contentItem("WORLDFEED#" + viewerId, contentSk(c), c, false)));
    }

    void deleteFeedCopy(UUID viewerId, StoredContent c) {
        db().deleteItem(r -> r.tableName(table).key(Map.of(
            "pk", s("WORLDFEED#" + viewerId), "sk", s(contentSk(c)))));
    }

    boolean migrationDone(String id) {
        var item = db().getItem(r -> r.tableName(table).key(Map.of(
            "pk", s("WORLDMIGRATION#" + id), "sk", s("DONE")))).item();
        return item != null && !item.isEmpty();
    }

    void markMigrationDone(String id, String summary) {
        db().putItem(r -> r.tableName(table).item(Map.of(
            "pk", s("WORLDMIGRATION#" + id), "sk", s("DONE"),
            "ranAt", s(Instant.now().toString()),
            "summary", s(summary))));
    }

    /** Removes the author's copy and every copy it was actually fanned out to. */
    void deleteContent(StoredContent content) {
        String sk = contentSk(content);
        db().deleteItem(r -> r.tableName(table).key(Map.of(
            "pk", s("WORLDPOST#" + content.authorId()), "sk", s(sk))));
        for (UUID viewer : content.viewers()) {
            db().deleteItem(r -> r.tableName(table).key(Map.of(
                "pk", s("WORLDFEED#" + viewer), "sk", s(sk))));
        }
    }

    /**
     * Everything one author sent this viewer. Pages the viewer's whole feed
     * partition rather than taking the first N and filtering after — a limit
     * applied before the author filter silently hides older posts behind a busy
     * feed, which reads as "they never posted" rather than as truncation.
     *
     * <p>Still the viewer's own partition, so it can only ever return what they
     * were actually sent.
     */
    List<StoredContent> feedByAuthor(UUID viewerId, UUID authorId, String kind, int limit) {
        Instant now = Instant.now();
        List<StoredContent> out = new ArrayList<>();
        for (var it : queryPrefix("WORLDFEED#" + viewerId, contentPrefix(kind))) {
            if (!authorId.toString().equals(attr(it, "authorId"))) continue;
            StoredContent c = readContent(it);
            if (c.expiresAt() != null && c.expiresAt().isBefore(now)) continue;
            out.add(c);
            if (out.size() >= limit) break;
        }
        out.sort(java.util.Comparator.comparing(StoredContent::createdAt).reversed());
        return out;
    }

    // ---- story seen state -------------------------------------------------

    void markStorySeen(UUID viewerId, UUID contentId) {
        db().putItem(r -> r.tableName(table).item(Map.of(
            "pk", s("WORLDSEEN#" + viewerId),
            "sk", s("STORY#" + contentId),
            "seenAt", s(Instant.now().toString()),
            // Outlives the story it refers to by a day, then sweeps itself.
            "ttl", n(Instant.now().plusSeconds(172_800).getEpochSecond()))));
    }

    java.util.Set<UUID> seenStories(UUID viewerId) {
        java.util.Set<UUID> out = new LinkedHashSet<>();
        for (var it : queryPrefix("WORLDSEEN#" + viewerId, "STORY#")) {
            out.add(UUID.fromString(it.get("sk").s().substring("STORY#".length())));
        }
        return out;
    }

    // ---- rich profile -----------------------------------------------------

    /** Stored as one JSON attribute on the existing WORLDUSER#/PROFILE item, so
     *  reading an identity stays a single get. */
    void putRichProfile(UUID profileId, WorldRichProfileDto profile) {
        Map<String, AttributeValue> values = new HashMap<>();
        values.put(":p", s(writeJson(profile)));
        db().updateItem(r -> r.tableName(table)
            .key(Map.of("pk", s("WORLDUSER#" + profileId), "sk", s("PROFILE")))
            .updateExpression("SET richJson = :p")
            .expressionAttributeValues(values));
    }

    Optional<WorldRichProfileDto> getRichProfile(UUID profileId) {
        var item = db().getItem(r -> r.tableName(table).key(Map.of(
            "pk", s("WORLDUSER#" + profileId), "sk", s("PROFILE")))).item();
        if (item == null || item.isEmpty()) return Optional.empty();
        return Optional.ofNullable(readJson(item, "richJson",
            new TypeReference<WorldRichProfileDto>() {}));
    }

    // ---- query helper -----------------------------------------------------

    private List<Map<String, AttributeValue>> queryPrefix(String pk, String skPrefix) {
        List<Map<String, AttributeValue>> out = new ArrayList<>();
        Map<String, AttributeValue> start = null;
        do {
            QueryRequest.Builder q = QueryRequest.builder()
                .tableName(table)
                .keyConditionExpression("pk = :p AND begins_with(sk, :s)")
                .expressionAttributeValues(Map.of(":p", s(pk), ":s", s(skPrefix)));
            if (start != null && !start.isEmpty()) q.exclusiveStartKey(start);
            QueryResponse resp = db().query(q.build());
            out.addAll(resp.items());
            start = resp.lastEvaluatedKey();
        } while (start != null && !start.isEmpty());
        return out;
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
