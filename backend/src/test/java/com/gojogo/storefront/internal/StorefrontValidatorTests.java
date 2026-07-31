package com.gojogo.storefront.internal;

import com.gojogo.storefront.StorefrontBlock;
import com.gojogo.storefront.StorefrontRef;
import com.gojogo.storefront.StorefrontRefKind;
import com.gojogo.storefront.StorefrontSurface;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The whole write contract of SPECS §9, checked without a database.
 *
 * <p>This is where the milestone's correctness lives: a storefront is authored
 * by a console this repo doesn't contain, so the only defence against a document
 * that renders as nonsense is refusing it at the door with a message that says
 * which block and why.
 */
class StorefrontValidatorTests {

    private static final int BLOCKS = 24;
    private static final int REFS = 24;

    private static List<StorefrontBlock> validate(StorefrontSurface surface,
                                                  StorefrontBlock... blocks) {
        return StorefrontValidator.validate(surface, List.of(blocks), BLOCKS, REFS);
    }

    private static List<StorefrontBlock> merchant(StorefrontBlock... blocks) {
        return validate(StorefrontSurface.MERCHANT_STOREFRONT, blocks);
    }

    private static void assertBadRequest(StorefrontSurface surface, StorefrontBlock block,
                                         String messageFragment) {
        assertThatThrownBy(() -> validate(surface, block))
            .isInstanceOf(ResponseStatusException.class)
            .satisfies(e -> assertThat(((ResponseStatusException) e).getStatusCode())
                .isEqualTo(HttpStatus.BAD_REQUEST))
            .hasMessageContaining(messageFragment);
    }

    // MARK: The closed set

    @Test
    void acceptsEveryBlockTypeOnAMerchantStorefront() {
        UUID item = UUID.randomUUID();
        List<StorefrontBlock> out = merchant(
            StorefrontBlock.hero("a", "Open late", "Until 2am", "https://cdn/x.jpg", null, null),
            StorefrontBlock.featuredItems("b", "Popular", List.of(item)),
            StorefrontBlock.collection("c", "Under $10", List.of(item)),
            StorefrontBlock.promoBanner("d", UUID.randomUUID()),
            StorefrontBlock.mediaRow("e", "From the kitchen",
                List.of(new StorefrontRef(StorefrontRefKind.POST, UUID.randomUUID()))),
            StorefrontBlock.text("f", "About", "Family run since 1998."),
            StorefrontBlock.info("g", "Details"));
        assertThat(out).hasSize(7);
    }

    /** The error has to name the type, because the author's next move is to fix
     *  the string they typed. */
    @Test
    void unknownTypeIsRefusedByName() {
        StorefrontBlock alien = new StorefrontBlock("a", "carousel_3d", null, null, null, null,
            null, null, null, null, null, null);
        assertBadRequest(StorefrontSurface.MERCHANT_STOREFRONT, alien, "carousel_3d");
    }

    /** A block set is closed *per surface*: a menu collection on a brand's home
     *  page names dishes nobody can resolve. */
    @Test
    void catalogBlocksAreRefusedOnABusinessHome() {
        assertBadRequest(StorefrontSurface.BUSINESS_HOME,
            StorefrontBlock.collection("a", "Under $10", List.of(UUID.randomUUID())),
            "which this page doesn't take");
        assertBadRequest(StorefrontSurface.BUSINESS_HOME,
            StorefrontBlock.promoBanner("a", UUID.randomUUID()),
            "which this page doesn't take");
    }

    @Test
    void businessHomeTakesTheContentBlocks() {
        assertThat(validate(StorefrontSurface.BUSINESS_HOME,
            StorefrontBlock.hero("a", "We ship daily", null, null, null, null),
            StorefrontBlock.text("b", null, "Ask us anything."),
            StorefrontBlock.mediaRow("c", null,
                List.of(new StorefrontRef(StorefrontRefKind.VIDEO, UUID.randomUUID()))))).hasSize(3);
    }

    // MARK: Required properties

    @Test
    void aHeroNeedsAHeadline() {
        assertBadRequest(StorefrontSurface.MERCHANT_STOREFRONT,
            StorefrontBlock.hero("a", "   ", null, "https://cdn/x.jpg", null, null),
            "needs a headline");
    }

    @Test
    void aCollectionNeedsATitleAndItems() {
        assertBadRequest(StorefrontSurface.MERCHANT_STOREFRONT,
            StorefrontBlock.collection("a", null, List.of(UUID.randomUUID())), "needs a title");
        assertBadRequest(StorefrontSurface.MERCHANT_STOREFRONT,
            StorefrontBlock.collection("a", "Empty", List.of()), "lists no items");
    }

    @Test
    void textNeedsABody() {
        assertBadRequest(StorefrontSurface.MERCHANT_STOREFRONT,
            StorefrontBlock.text("a", "About", null), "needs a body");
    }

    /** A featured rail may go untitled — the section header is optional in a
     *  way a collection's is not, since a collection *is* its title. */
    @Test
    void featuredItemsMayBeUntitled() {
        assertThat(merchant(StorefrontBlock.featuredItems("a", null, List.of(UUID.randomUUID()))))
            .hasSize(1);
    }

    // MARK: Properties a type has no meaning for

    @Test
    void aHeroCarryingProseIsRefused() {
        StorefrontBlock confused = new StorefrontBlock("a", "hero", null, "Open late", null,
            "…and here is our whole story", null, null, null, null, null, null);
        assertBadRequest(StorefrontSurface.MERCHANT_STOREFRONT, confused, "has no body");
    }

    /** An info block renders live hours; a copy of them would be wrong by
     *  Sunday, so there is nowhere to put one. */
    @Test
    void anInfoBlockHoldsNothingButATitle() {
        StorefrontBlock copied = new StorefrontBlock("a", "info", "Hours", null, null,
            "Mon–Fri 9–5", null, null, null, null, null, null);
        assertBadRequest(StorefrontSurface.MERCHANT_STOREFRONT, copied, "has no body");
    }

    // MARK: Buttons

    @Test
    void aButtonNeedsBothALabelAndADestination() {
        assertBadRequest(StorefrontSurface.MERCHANT_STOREFRONT,
            StorefrontBlock.hero("a", "Order now", null, null, "See the menu", null),
            "both a ctaLabel and a ctaTarget");
        assertBadRequest(StorefrontSurface.MERCHANT_STOREFRONT,
            StorefrontBlock.hero("a", "Order now", null, null, null,
                new StorefrontRef(StorefrontRefKind.SECTION, UUID.randomUUID())),
            "both a ctaLabel and a ctaTarget");
    }

    @Test
    void aButtonGoesToAnItemOrASection() {
        assertThat(merchant(StorefrontBlock.hero("a", "Order now", null, null, "See the menu",
            new StorefrontRef(StorefrontRefKind.SECTION, UUID.randomUUID())))).hasSize(1);
        assertBadRequest(StorefrontSurface.MERCHANT_STOREFRONT,
            StorefrontBlock.hero("a", "Order now", null, null, "Save 10%",
                new StorefrontRef(StorefrontRefKind.PROMOTION, UUID.randomUUID())),
            "a button goes to an ITEM or a SECTION");
    }

    @Test
    void aMediaRowTakesOnlyPostsAndVideos() {
        assertBadRequest(StorefrontSurface.MERCHANT_STOREFRONT,
            StorefrontBlock.mediaRow("a", null,
                List.of(new StorefrontRef(StorefrontRefKind.ITEM, UUID.randomUUID()))),
            "can't hold a ITEM");
    }

    // MARK: Ids and limits

    @Test
    void blockIdsAreUniqueWithinAPage() {
        assertThatThrownBy(() -> merchant(
            StorefrontBlock.text("about", null, "One"),
            StorefrontBlock.text("about", null, "Two")))
            .hasMessageContaining("share the id 'about'");
    }

    @Test
    void aBlockWithoutAnIdIsRefused() {
        assertBadRequest(StorefrontSurface.MERCHANT_STOREFRONT,
            StorefrontBlock.text(" ", null, "Body"), "has no id");
    }

    @Test
    void tooManyBlocksIsRefusedBeforeAnythingElse() {
        List<StorefrontBlock> many = new ArrayList<>();
        for (int i = 0; i < 25; i++) {
            many.add(StorefrontBlock.text("t" + i, null, "Body"));
        }
        assertThatThrownBy(() ->
            StorefrontValidator.validate(StorefrontSurface.MERCHANT_STOREFRONT, many, BLOCKS, REFS))
            .hasMessageContaining("at most 24 blocks");
    }

    @Test
    void aRailLongerThanTheLimitIsRefused() {
        List<UUID> ids = new ArrayList<>();
        for (int i = 0; i < 25; i++) {
            ids.add(UUID.randomUUID());
        }
        assertBadRequest(StorefrontSurface.MERCHANT_STOREFRONT,
            StorefrontBlock.featuredItems("a", null, ids), "more than 24 things");
    }

    /** The same dish twice in one rail is a mistake, not an intent — collapsed
     *  rather than refused, because there is only one thing the author could
     *  have meant. */
    @Test
    void repeatedItemsCollapse() {
        UUID item = UUID.randomUUID();
        List<StorefrontBlock> out = merchant(
            StorefrontBlock.featuredItems("a", null, List.of(item, item, item)));
        assertThat(out.getFirst().itemIds()).containsExactly(item);
    }

    @Test
    void emptyStringsAreNotValues() {
        List<StorefrontBlock> out = merchant(
            StorefrontBlock.hero("a", "  Open late  ", "   ", "", null, null));
        assertThat(out.getFirst().headline()).isEqualTo("Open late");
        assertThat(out.getFirst().subheadline()).isNull();
        assertThat(out.getFirst().mediaUrl()).isNull();
    }

    @Test
    void anEmptyPageIsAValidPage() {
        assertThat(StorefrontValidator.validate(StorefrontSurface.MERCHANT_STOREFRONT, null,
            BLOCKS, REFS)).isEmpty();
    }
}
