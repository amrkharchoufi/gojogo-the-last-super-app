package com.gojogo.assistant.internal;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/*
 * The module's repositories, together because each is a handful of finders and
 * they are read as a set. Nothing outside this package sees them.
 */

interface AssistantConversationRepository extends JpaRepository<AssistantConversation, UUID> {

    List<AssistantConversation> findByUserIdAndStateOrderByLastActiveAtDesc(
        UUID userId, AssistantConversationState state, Pageable page);

    Optional<AssistantConversation> findByIdAndUserId(UUID id, UUID userId);
}

interface AssistantMessageRepository extends JpaRepository<AssistantMessage, UUID> {

    List<AssistantMessage> findByConversationIdOrderBySeqAsc(UUID conversationId);

    /** The tail the loop feeds to the model, newest first — reversed by the
     *  caller. Reading the whole thread and dropping most of it is how a long
     *  conversation turns into a slow one. */
    List<AssistantMessage> findByConversationIdOrderBySeqDesc(UUID conversationId, Pageable page);

    @Query("select coalesce(max(m.seq), 0) from AssistantMessage m "
        + "where m.conversationId = :conversationId")
    int highestSeq(@Param("conversationId") UUID conversationId);

    /**
     * User messages this person sent in the window — MADELEINE.md §4's
     * {@code turnsPerUserPerHour}.
     *
     * <p>Counted from the ledger rather than from a counter in memory, so the
     * limit holds across every Fargate task rather than per instance. The two
     * entities are joined by hand because cross-entity references in this
     * codebase are plain ids, never mapped associations.
     */
    @Query("select count(m) from AssistantMessage m, AssistantConversation c "
        + "where m.conversationId = c.id and c.userId = :userId "
        + "and m.role = com.gojogo.assistant.internal.AssistantMessageRole.USER "
        + "and m.createdAt > :since")
    long turnsSince(@Param("userId") UUID userId, @Param("since") OffsetDateTime since);
}

interface AssistantTaskRepository extends JpaRepository<AssistantTask, UUID> {

    List<AssistantTask> findByUserIdOrderByCreatedAtDesc(UUID userId, Pageable page);
}

interface AssistantActionRepository extends JpaRepository<AssistantAction, UUID> {

    List<AssistantAction> findByConversationIdOrderByCreatedAtDesc(UUID conversationId,
                                                                  Pageable page);

    /**
     * A live card for this exact tool in this turn.
     *
     * <p>§5 step 5: one action, one approval. A model that calls the same gated
     * tool twice while a card is already on screen must not produce a second
     * card — it gets told the first one is still waiting.
     */
    Optional<AssistantAction> findFirstByTurnIdAndToolNameAndStateOrderByCreatedAtDesc(
        UUID turnId, String toolName, AssistantActionState state);
}
