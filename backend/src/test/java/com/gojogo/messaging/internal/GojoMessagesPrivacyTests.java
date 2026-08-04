package com.gojogo.messaging.internal;

import com.gojogo.messaging.MessageSent;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * The Phase 2f rules that are cheap to state and expensive to get wrong.
 *
 * <p>There is no local DynamoDB, so the storage layer isn't covered here — these
 * pin the pure logic where a mistake would leak something, plus one guard that
 * fails the build if somebody widens the audience model.
 */
class GojoMessagesPrivacyTests {

    /**
     * The load-bearing one. A GojoMessages post is seen by the author's contacts
     * or by the circles they picked and by nobody else, <em>ever</em> — so this
     * enum must never grow a PUBLIC constant. If it does, every "can this leak?"
     * argument in ARCHITECTURE §2b decision 4 stops holding, and this test is the
     * cheapest place to find that out.
     */
    @Test
    void audienceCanNeverBePublic() {
        assertEquals(2, WorldAudience.values().length,
            "Adding an audience means re-deriving the privacy argument in ARCHITECTURE decision 4");
        for (WorldAudience a : WorldAudience.values()) {
            assertTrue(a == WorldAudience.CONTACTS || a == WorldAudience.CIRCLES,
                "Unexpected audience " + a + " — a GojoMessages post is never public");
        }
    }

    /** A reader must not learn which of the author's circles they landed in. */
    @Test
    void readerCopyStripsTheAudience() {
        UUID circle = UUID.randomUUID();
        WorldContentDto authored = new WorldContentDto(
            UUID.randomUUID(), UUID.randomUUID(), "Amine", null, "post", "hi",
            List.of(), Instant.now(), null, false, WorldAudience.CIRCLES, List.of(circle));

        assertEquals(WorldAudience.CIRCLES, authored.audience(), "the author sees their own choice");

        WorldContentDto reader = authored.withoutAudience();
        assertNull(reader.audience(), "a reader is never told the audience");
        assertNull(reader.circleIds(), "a reader is never told which circle they're in");
        assertEquals(authored.text(), reader.text(), "everything else survives the strip");
        assertEquals(authored.authorId(), reader.authorId(),
            "authorId stays — it's what lets the client apply a private rename");
    }

    /** A private rename wins over the name the contact set for themselves. */
    @Test
    void aliasBeatsTheirOwnName() {
        UUID id = UUID.randomUUID();
        assertEquals("Mum",
            new ContactDto(id, "Fatima B.", null, "+212600000000", "Mum", Instant.now())
                .effectiveName());
        assertEquals("Fatima B.",
            new ContactDto(id, "Fatima B.", null, "+212600000000", null, Instant.now())
                .effectiveName());
        assertEquals("Fatima B.",
            new ContactDto(id, "Fatima B.", null, "+212600000000", "   ", Instant.now())
                .effectiveName(),
            "a blank alias is not a rename");
    }

    /**
     * A push is the one name the server renders on a specific viewer's behalf,
     * so it has to carry the recipient's own rename rather than the sender's name.
     */
    @Test
    void pushTitleIsResolvedPerRecipient() {
        UUID sender = UUID.randomUUID();
        UUID renamer = UUID.randomUUID();
        UUID everyoneElse = UUID.randomUUID();

        MessageSent event = new MessageSent(UUID.randomUUID(), UUID.randomUUID(), sender,
            "Youssef", "hey", List.of(renamer, everyoneElse), Map.of(renamer, "Boss"), 2, "AAAA");

        assertEquals("Boss", event.titleFor(renamer), "the renamer sees their own name for him");
        assertEquals("Youssef", event.titleFor(everyoneElse), "everybody else sees the real name");
    }

    /** An event published before anybody had renamed anyone must still work. */
    @Test
    void pushTitleFallsBackWhenThereAreNoRenames() {
        UUID recipient = UUID.randomUUID();
        MessageSent noMap = new MessageSent(UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID(),
            "Youssef", "hey", List.of(recipient), null, null, null);
        assertEquals("Youssef", noMap.titleFor(recipient));
    }

    /** Empty rich profiles round-trip as empty lists, not nulls the UI must guard. */
    @Test
    void emptyRichProfileHasNoNulls() {
        WorldRichProfileDto empty = WorldRichProfileDto.empty();
        assertTrue(empty.languages().isEmpty());
        assertTrue(empty.interests().isEmpty());
        assertTrue(empty.favouriteBooks().isEmpty());
        assertTrue(empty.favouriteGames().isEmpty());
    }
}
