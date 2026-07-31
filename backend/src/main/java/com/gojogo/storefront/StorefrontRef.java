package com.gojogo.storefront;

import java.util.UUID;

/**
 * One thing a block points at: {@code {"kind": "ITEM", "id": "…"}}.
 *
 * <p>Kinds are upper-case here and block types are lower_snake, which looks
 * inconsistent until you notice they are different things: a block type is part
 * of the document format SPECS §9 fixes, a ref kind is an enum this module
 * happens to serialize.
 */
public record StorefrontRef(StorefrontRefKind kind, UUID id) {
}
