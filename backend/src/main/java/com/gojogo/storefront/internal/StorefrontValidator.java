package com.gojogo.storefront.internal;

import com.gojogo.storefront.StorefrontBlock;
import com.gojogo.storefront.StorefrontBlockType;
import com.gojogo.storefront.StorefrontRef;
import com.gojogo.storefront.StorefrontRefKind;
import com.gojogo.storefront.StorefrontSurface;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * Turns a submitted list of blocks into a document that is worth storing, or a
 * 400 that says exactly which block is wrong and why.
 *
 * <p>Pure and static: no repository, no Spring, nothing to mock. The whole
 * milestone's correctness risk lives in this file, and it is the one part of it
 * that can be tested exhaustively without a database (which, on this machine, is
 * the only kind of test there is).
 *
 * <p><strong>Strict on the way in.</strong> Beyond the obvious — unknown type,
 * missing headline, 900 blocks — it refuses a block that carries a property its
 * type has no meaning for. That looks pedantic until you picture the alternative:
 * a page builder that quietly sends {@code body} on a hero, a reviewer who sees
 * their text in the editor's preview and never on the page, and a bug report
 * about "text that doesn't save". Better to say no at the write.
 *
 * <p>Every message names the block by its author-chosen id, because a page
 * builder's error banner has to be able to highlight one block.
 */
final class StorefrontValidator {

    private StorefrontValidator() {
    }

    static final int MAX_ID_CHARS = 64;
    static final int MAX_TITLE_CHARS = 80;
    static final int MAX_HEADLINE_CHARS = 120;
    static final int MAX_SUBHEADLINE_CHARS = 200;
    static final int MAX_CTA_LABEL_CHARS = 40;
    static final int MAX_URL_CHARS = 600;
    static final int MAX_BODY_CHARS = 4000;

    /** What a hero's button may point at. A promotion is not a destination — it
     *  is a thing to show, which is what {@code promo_banner} is for. */
    private static final Set<StorefrontRefKind> CTA_KINDS =
        Set.of(StorefrontRefKind.ITEM, StorefrontRefKind.SECTION);

    private static final Set<StorefrontRefKind> MEDIA_KINDS =
        Set.of(StorefrontRefKind.POST, StorefrontRefKind.VIDEO);

    /**
     * @param maxBlocks   config knob, so a page that grows past what a phone can
     *                    scroll is a policy decision rather than a deploy
     * @param maxRefs     per block — the cap on a rail's length
     * @return the same blocks, normalized (trimmed strings, de-duplicated ids)
     */
    static List<StorefrontBlock> validate(StorefrontSurface surface, List<StorefrontBlock> blocks,
                                          int maxBlocks, int maxRefs) {
        List<StorefrontBlock> submitted = blocks == null ? List.of() : blocks;
        if (submitted.size() > maxBlocks) {
            throw bad("A page can hold at most " + maxBlocks + " blocks; this one has "
                + submitted.size() + ".");
        }
        Set<String> seenIds = new LinkedHashSet<>();
        List<StorefrontBlock> out = new ArrayList<>(submitted.size());
        for (int i = 0; i < submitted.size(); i++) {
            StorefrontBlock block = submitted.get(i);
            if (block == null) {
                throw bad("Block " + (i + 1) + " is empty.");
            }
            String id = trimmed(block.id());
            if (id == null) {
                throw bad("Block " + (i + 1) + " has no id.");
            }
            if (id.length() > MAX_ID_CHARS) {
                throw bad("Block id '" + id + "' is longer than " + MAX_ID_CHARS + " characters.");
            }
            if (!seenIds.add(id)) {
                throw bad("Two blocks share the id '" + id + "'.");
            }
            out.add(validateBlock(surface, block, id, maxRefs));
        }
        return List.copyOf(out);
    }

    private static StorefrontBlock validateBlock(StorefrontSurface surface, StorefrontBlock block,
                                                 String id, int maxRefs) {
        StorefrontBlockType type = StorefrontBlockType.of(block.type())
            .orElseThrow(() -> bad("Block '" + id + "' has an unknown type '" + block.type()
                + "'. Known types: " + wireNames(StorefrontBlockType.values()) + "."));
        if (!surface.allows(type)) {
            throw bad("Block '" + id + "' is a " + type.wire() + ", which this page doesn't take. "
                + "Allowed here: " + wireNames(surface.allowedTypes().toArray(StorefrontBlockType[]::new)) + ".");
        }

        String title = text(id, "title", block.title(), MAX_TITLE_CHARS);
        String headline = text(id, "headline", block.headline(), MAX_HEADLINE_CHARS);
        String subheadline = text(id, "subheadline", block.subheadline(), MAX_SUBHEADLINE_CHARS);
        String body = text(id, "body", block.body(), MAX_BODY_CHARS);
        String mediaUrl = text(id, "mediaUrl", block.mediaUrl(), MAX_URL_CHARS);
        String ctaLabel = text(id, "ctaLabel", block.ctaLabel(), MAX_CTA_LABEL_CHARS);
        List<UUID> itemIds = ids(id, block.itemIds(), maxRefs);
        List<StorefrontRef> media = refs(id, block.media(), MEDIA_KINDS, maxRefs);

        switch (type) {
            case HERO -> {
                require(id, "headline", headline);
                forbid(id, type, "body", body);
                forbid(id, type, "title", title);
                forbidRefs(id, type, "itemIds", itemIds);
                forbid(id, type, "promotionId", block.promotionId());
                forbidRefs(id, type, "media", media);
                if (block.ctaTarget() != null && !CTA_KINDS.contains(block.ctaTarget().kind())) {
                    throw bad("Block '" + id + "' has a button pointing at a "
                        + block.ctaTarget().kind() + "; a button goes to an ITEM or a SECTION.");
                }
                if (block.ctaTarget() != null && block.ctaTarget().id() == null) {
                    throw bad("Block '" + id + "' has a button with no destination id.");
                }
                // Both or neither: a labelled button with nowhere to go is a
                // dead tap, and a destination with no label is invisible.
                if ((ctaLabel == null) != (block.ctaTarget() == null)) {
                    throw bad("Block '" + id + "' needs both a ctaLabel and a ctaTarget, or neither.");
                }
                return StorefrontBlock.hero(id, headline, subheadline, mediaUrl, ctaLabel,
                    block.ctaTarget());
            }
            case FEATURED_ITEMS, COLLECTION -> {
                if (type == StorefrontBlockType.COLLECTION) {
                    require(id, "title", title);
                }
                if (itemIds.isEmpty()) {
                    throw bad("Block '" + id + "' lists no items.");
                }
                forbidPlain(id, type, headline, subheadline, body, mediaUrl, ctaLabel);
                forbid(id, type, "ctaTarget", block.ctaTarget());
                forbid(id, type, "promotionId", block.promotionId());
                forbidRefs(id, type, "media", media);
                return type == StorefrontBlockType.COLLECTION
                    ? StorefrontBlock.collection(id, title, itemIds)
                    : StorefrontBlock.featuredItems(id, title, itemIds);
            }
            case PROMO_BANNER -> {
                if (block.promotionId() == null) {
                    throw bad("Block '" + id + "' names no promotion.");
                }
                forbidPlain(id, type, headline, subheadline, body, mediaUrl, ctaLabel);
                forbid(id, type, "title", title);
                forbid(id, type, "ctaTarget", block.ctaTarget());
                forbidRefs(id, type, "itemIds", itemIds);
                forbidRefs(id, type, "media", media);
                return StorefrontBlock.promoBanner(id, block.promotionId());
            }
            case MEDIA_ROW -> {
                if (media.isEmpty()) {
                    throw bad("Block '" + id + "' imports no posts or videos.");
                }
                forbidPlain(id, type, headline, subheadline, body, mediaUrl, ctaLabel);
                forbid(id, type, "ctaTarget", block.ctaTarget());
                forbid(id, type, "promotionId", block.promotionId());
                forbidRefs(id, type, "itemIds", itemIds);
                return StorefrontBlock.mediaRow(id, title, media);
            }
            case TEXT -> {
                require(id, "body", body);
                forbidPlain(id, type, headline, subheadline, null, mediaUrl, ctaLabel);
                forbid(id, type, "ctaTarget", block.ctaTarget());
                forbid(id, type, "promotionId", block.promotionId());
                forbidRefs(id, type, "itemIds", itemIds);
                forbidRefs(id, type, "media", media);
                return StorefrontBlock.text(id, title, body);
            }
            case INFO -> {
                // Everything an info block shows is read live from the merchant
                // or business it belongs to. A property here would be a copy,
                // and a copy of opening hours is wrong by next Sunday.
                forbidPlain(id, type, headline, subheadline, body, mediaUrl, ctaLabel);
                forbid(id, type, "ctaTarget", block.ctaTarget());
                forbid(id, type, "promotionId", block.promotionId());
                forbidRefs(id, type, "itemIds", itemIds);
                forbidRefs(id, type, "media", media);
                return StorefrontBlock.info(id, title);
            }
        }
        throw bad("Block '" + id + "' could not be read.");
    }

    // MARK: Property helpers

    private static String text(String id, String property, String value, int max) {
        String trimmed = trimmed(value);
        if (trimmed != null && trimmed.length() > max) {
            throw bad("Block '" + id + "' has a " + property + " longer than " + max
                + " characters.");
        }
        return trimmed;
    }

    private static List<UUID> ids(String id, List<UUID> values, int maxRefs) {
        if (values == null) {
            return List.of();
        }
        Set<UUID> unique = new LinkedHashSet<>();
        for (UUID value : values) {
            if (value == null) {
                throw bad("Block '" + id + "' has an empty id in its list.");
            }
            unique.add(value);
        }
        if (unique.size() > maxRefs) {
            throw bad("Block '" + id + "' points at more than " + maxRefs + " things.");
        }
        return List.copyOf(unique);
    }

    private static List<StorefrontRef> refs(String id, List<StorefrontRef> values,
                                            Set<StorefrontRefKind> allowed, int maxRefs) {
        if (values == null) {
            return List.of();
        }
        Set<StorefrontRef> unique = new LinkedHashSet<>();
        for (StorefrontRef ref : values) {
            if (ref == null || ref.id() == null || ref.kind() == null) {
                throw bad("Block '" + id + "' has an incomplete reference.");
            }
            if (!allowed.contains(ref.kind())) {
                throw bad("Block '" + id + "' can't hold a " + ref.kind() + ".");
            }
            unique.add(ref);
        }
        if (unique.size() > maxRefs) {
            throw bad("Block '" + id + "' points at more than " + maxRefs + " things.");
        }
        return List.copyOf(unique);
    }

    private static void require(String id, String property, String value) {
        if (value == null) {
            throw bad("Block '" + id + "' needs a " + property + ".");
        }
    }

    private static void forbid(String id, StorefrontBlockType type, String property, Object value) {
        if (value != null) {
            throw bad("A " + type.wire() + " block has no " + property + " (block '" + id + "').");
        }
    }

    private static void forbidRefs(String id, StorefrontBlockType type, String property,
                                   List<?> values) {
        if (values != null && !values.isEmpty()) {
            throw bad("A " + type.wire() + " block has no " + property + " (block '" + id + "').");
        }
    }

    /** The five free-text properties in one call — every type forbids most of
     *  them, and spelling that out five times per branch buries the rules that
     *  actually differ. */
    private static void forbidPlain(String id, StorefrontBlockType type, String headline,
                                    String subheadline, String body, String mediaUrl,
                                    String ctaLabel) {
        forbid(id, type, "headline", headline);
        forbid(id, type, "subheadline", subheadline);
        forbid(id, type, "body", body);
        forbid(id, type, "mediaUrl", mediaUrl);
        forbid(id, type, "ctaLabel", ctaLabel);
    }

    private static String trimmed(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private static String wireNames(StorefrontBlockType[] types) {
        return java.util.Arrays.stream(types)
            .map(StorefrontBlockType::wire)
            .sorted()
            .reduce((a, b) -> a + ", " + b)
            .orElse("");
    }

    private static ResponseStatusException bad(String message) {
        return new ResponseStatusException(HttpStatus.BAD_REQUEST, message);
    }
}
