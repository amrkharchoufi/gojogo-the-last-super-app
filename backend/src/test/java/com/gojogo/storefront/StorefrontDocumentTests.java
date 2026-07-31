package com.gojogo.storefront;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Reference extraction — the half of the write contract the platform module
 * hands back to the vertical.
 *
 * <p>Worth its own tests because a missed id is not a rendering bug: it is a
 * restaurant page featuring a competitor's dish, which is the one failure this
 * whole check exists to prevent.
 */
class StorefrontDocumentTests {

    private static StorefrontDocument doc(StorefrontBlock... blocks) {
        return new StorefrontDocument(1, List.of(blocks), null);
    }

    @Test
    void collectsItemIdsFromEveryRail() {
        UUID a = UUID.randomUUID();
        UUID b = UUID.randomUUID();
        StorefrontDocument document = doc(
            StorefrontBlock.featuredItems("f", null, List.of(a)),
            StorefrontBlock.collection("c", "Under $10", List.of(b)));
        assertThat(document.references(StorefrontRefKind.ITEM)).containsExactly(a, b);
    }

    /** A hero's button is a reference too. Missing it would leave the one place
     *  a page can point straight at a dish unchecked. */
    @Test
    void collectsAHeroButtonsDestination() {
        UUID section = UUID.randomUUID();
        StorefrontDocument document = doc(StorefrontBlock.hero("h", "Order now", null, null,
            "See the menu", new StorefrontRef(StorefrontRefKind.SECTION, section)));
        assertThat(document.references(StorefrontRefKind.SECTION)).containsExactly(section);
        assertThat(document.references(StorefrontRefKind.ITEM)).isEmpty();
    }

    @Test
    void separatesPostsFromVideosInOneMediaRow() {
        UUID post = UUID.randomUUID();
        UUID video = UUID.randomUUID();
        StorefrontDocument document = doc(StorefrontBlock.mediaRow("m", null, List.of(
            new StorefrontRef(StorefrontRefKind.POST, post),
            new StorefrontRef(StorefrontRefKind.VIDEO, video))));
        assertThat(document.references(StorefrontRefKind.POST)).containsExactly(post);
        assertThat(document.references(StorefrontRefKind.VIDEO)).containsExactly(video);
    }

    /** One id used twice is checked once. */
    @Test
    void referencesAreDeduplicated() {
        UUID item = UUID.randomUUID();
        StorefrontDocument document = doc(
            StorefrontBlock.featuredItems("f", null, List.of(item)),
            StorefrontBlock.collection("c", "Again", List.of(item)));
        assertThat(document.references(StorefrontRefKind.ITEM)).containsExactly(item);
    }

    @Test
    void promotionsAreFoundOnTheirBanner() {
        UUID promotion = UUID.randomUUID();
        assertThat(doc(StorefrontBlock.promoBanner("p", promotion))
            .references(StorefrontRefKind.PROMOTION)).containsExactly(promotion);
    }

    /** Version 0 is the one version no save can produce, which is what lets a
     *  client tell "never arranged" from "arranged, then emptied". */
    @Test
    void anEmptyDocumentIsVersionZero() {
        assertThat(StorefrontDocument.empty().version()).isZero();
        assertThat(StorefrontDocument.empty().isEmpty()).isTrue();
        assertThat(StorefrontDocument.empty().references(StorefrontRefKind.ITEM)).isEmpty();
    }
}
