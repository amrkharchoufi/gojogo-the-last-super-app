package com.gojogo.storefront;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.util.List;
import java.util.UUID;

/**
 * One block of a storefront, flat on the wire exactly as SPECS §9 describes it:
 * {@code {"type": "collection", "id": "b3", "title": "Under $10", "itemIds": [...]}}.
 *
 * <p><strong>Why one record with a superset of properties</strong> rather than a
 * sealed hierarchy with a Jackson type id: an unknown {@code type} has to come
 * back as a <em>400 naming the type</em>, and a polymorphic deserializer turns
 * it into a parse failure several layers below anything that could say that.
 * Keeping {@code type} a plain string and resolving it during validation is what
 * buys the good error message. The cost — properties that are null for most
 * types — is paid back by validation, which refuses a block carrying a property
 * its type has no meaning for, so a hero with a {@code body} never reaches
 * storage.
 *
 * <p>{@code id} is the author's, not the database's: a page builder needs stable
 * handles to reorder and re-edit blocks, and a server-minted id would change
 * under a document that is rewritten whole on every save.
 *
 * @param id           author-chosen, unique within the document
 * @param type         a {@link StorefrontBlockType} wire name
 * @param title        HERO / FEATURED_ITEMS / COLLECTION / MEDIA_ROW / TEXT / INFO
 * @param headline     HERO
 * @param subheadline  HERO
 * @param body         TEXT
 * @param mediaUrl     HERO
 * @param ctaLabel     HERO — with {@code ctaTarget}, or neither
 * @param ctaTarget    HERO — an ITEM or a SECTION
 * @param itemIds      FEATURED_ITEMS / COLLECTION
 * @param promotionId  PROMO_BANNER
 * @param media        MEDIA_ROW — POSTs and VIDEOs
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record StorefrontBlock(
    String id,
    String type,
    String title,
    String headline,
    String subheadline,
    String body,
    String mediaUrl,
    String ctaLabel,
    StorefrontRef ctaTarget,
    List<UUID> itemIds,
    UUID promotionId,
    List<StorefrontRef> media
) {

    public static StorefrontBlock hero(String id, String headline, String subheadline,
                                       String mediaUrl, String ctaLabel, StorefrontRef ctaTarget) {
        return new StorefrontBlock(id, StorefrontBlockType.HERO.wire(), null, headline,
            subheadline, null, mediaUrl, ctaLabel, ctaTarget, null, null, null);
    }

    public static StorefrontBlock featuredItems(String id, String title, List<UUID> itemIds) {
        return new StorefrontBlock(id, StorefrontBlockType.FEATURED_ITEMS.wire(), title, null,
            null, null, null, null, null, itemIds, null, null);
    }

    public static StorefrontBlock collection(String id, String title, List<UUID> itemIds) {
        return new StorefrontBlock(id, StorefrontBlockType.COLLECTION.wire(), title, null,
            null, null, null, null, null, itemIds, null, null);
    }

    public static StorefrontBlock promoBanner(String id, UUID promotionId) {
        return new StorefrontBlock(id, StorefrontBlockType.PROMO_BANNER.wire(), null, null,
            null, null, null, null, null, null, promotionId, null);
    }

    public static StorefrontBlock mediaRow(String id, String title, List<StorefrontRef> media) {
        return new StorefrontBlock(id, StorefrontBlockType.MEDIA_ROW.wire(), title, null,
            null, null, null, null, null, null, null, media);
    }

    public static StorefrontBlock text(String id, String title, String body) {
        return new StorefrontBlock(id, StorefrontBlockType.TEXT.wire(), title, null,
            null, body, null, null, null, null, null, null);
    }

    public static StorefrontBlock info(String id, String title) {
        return new StorefrontBlock(id, StorefrontBlockType.INFO.wire(), title, null,
            null, null, null, null, null, null, null, null);
    }
}
