package com.gojogo.messaging.internal;

import com.gojogo.messaging.internal.MessagingRepository.HiddenHistory;
import com.gojogo.messaging.internal.MessagingRepository.StoredMessage;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Deleting a conversation used to last exactly as long as the next fetch: the
 * membership row went, the messages didn't, and re-opening the same 1:1 rejoined
 * the same thread with every message replayed into it. The watermark written by
 * {@code leave} is what makes it stick, and this pins the page trimming it feeds
 * — including the cursor, which is the part that quietly re-serves deleted
 * history if it keeps pointing backwards.
 *
 * <p>There is no local DynamoDB, so this covers the decision, not the storage.
 */
class HistoryClearTests {

    private static final UUID CONV = UUID.randomUUID();
    private static final Instant T0 = Instant.parse("2026-08-01T10:00:00Z");

    /** Newest-first, the order the repository hands pages back in. */
    private static List<StoredMessage> page(int count, int fromMinute) {
        List<StoredMessage> out = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            out.add(new StoredMessage(
                UUID.randomUUID(), CONV, UUID.randomUUID(), "text", "m",
                List.of(), null, null, Map.of(),
                T0.plusSeconds((fromMinute - i) * 60L), null, null, null, null));
        }
        return out;
    }

    private static HiddenHistory cleared(Instant at) {
        return new HiddenHistory(at, Set.of());
    }

    @Test
    void noWatermarkChangesNothing() {
        List<StoredMessage> full = page(30, 100);
        MessagingService.Page trimmed = MessagingService.trim(full, 30, HiddenHistory.NONE);
        assertEquals(full, trimmed.messages(), "an untouched thread is served whole");
        assertEquals(full.get(29).createdAt(), trimmed.nextBefore(),
            "a full page still offers the cursor for the one behind it");
    }

    @Test
    void everythingBeforeTheDeleteIsGone() {
        // Deleted after the newest message: the thread is empty for this user.
        MessagingService.Page trimmed =
            MessagingService.trim(page(30, 100), 30, cleared(T0.plusSeconds(200 * 60L)));
        assertTrue(trimmed.messages().isEmpty(), "nothing survives your own delete");
        assertNull(trimmed.nextBefore(), "and there is nothing older to page to");
    }

    @Test
    void messagesAfterTheDeleteSurvive() {
        // Minutes 100..71 in the page; deleted at minute 90.
        MessagingService.Page trimmed =
            MessagingService.trim(page(30, 100), 30, cleared(T0.plusSeconds(90 * 60L)));
        assertEquals(10, trimmed.messages().size(),
            "the ten sent after the delete are the thread now");
        assertTrue(trimmed.messages().stream()
                .allMatch(m -> m.createdAt().isAfter(T0.plusSeconds(90 * 60L))),
            "nothing at or before the watermark is served");
    }

    /**
     * The one that matters. A page is newest-first, so a single trimmed message
     * proves the rest of the thread is older than the delete — handing back a
     * cursor there would walk the client straight back into deleted history.
     */
    @Test
    void aTrimmedPageOffersNoCursor() {
        MessagingService.Page trimmed =
            MessagingService.trim(page(30, 100), 30, cleared(T0.plusSeconds(90 * 60L)));
        assertNull(trimmed.nextBefore(), "the trim is the end of this user's history");
    }

    @Test
    void aShortPageOffersNoCursorEither() {
        MessagingService.Page trimmed = MessagingService.trim(page(12, 100), 30, HiddenHistory.NONE);
        assertEquals(12, trimmed.messages().size());
        assertNull(trimmed.nextBefore(), "a page under the limit is the top of the thread");
    }

    // ---- individual messages ------------------------------------------------

    @Test
    void aDeletedMessageIsNotServed() {
        List<StoredMessage> full = page(30, 100);
        UUID gone = full.get(5).id();
        MessagingService.Page trimmed = MessagingService.trim(
            full, 30, new HiddenHistory(null, Set.of(gone)));
        assertEquals(29, trimmed.messages().size(), "one fewer, and only one");
        assertTrue(trimmed.messages().stream().noneMatch(m -> m.id().equals(gone)),
            "the deleted message is gone from the page");
    }

    /**
     * The trap the whole-thread watermark sets for this one. A trimmed watermark
     * page has nothing older behind it — but a deleted *message* says nothing
     * about the messages behind it, and reusing that shortcut would truncate the
     * thread at whichever message somebody happened to delete.
     */
    @Test
    void aDeletedMessageDoesNotEndTheThread() {
        List<StoredMessage> full = page(30, 100);
        MessagingService.Page trimmed = MessagingService.trim(
            full, 30, new HiddenHistory(null, Set.of(full.get(29).id())));
        assertEquals(full.get(29).createdAt(), trimmed.nextBefore(),
            "the cursor comes off the stored page, so deleting the oldest message "
                + "on it cannot cut the history off above it");
    }

    @Test
    void bothKindsOfHidingApplyAtOnce() {
        List<StoredMessage> full = page(30, 100);
        // Minutes 100..71; cleared at 90, and one of the survivors deleted too.
        UUID gone = full.get(2).id(); // minute 98
        MessagingService.Page trimmed = MessagingService.trim(
            full, 30, new HiddenHistory(T0.plusSeconds(90 * 60L), Set.of(gone)));
        assertEquals(9, trimmed.messages().size(), "ten after the watermark, minus the deleted one");
        assertTrue(trimmed.messages().stream().noneMatch(m -> m.id().equals(gone)));
        assertNull(trimmed.nextBefore(), "the watermark still ends the history");
    }
}
