package com.gojogo.payments;

import java.util.UUID;

/**
 * Names one account: whose it is, and which pocket.
 *
 * <p>The singletons ({@link OwnerKind#PLATFORM}, {@link OwnerKind#EXTERNAL})
 * use the nil UUID so that "one row per (kind, id, bucket, currency)" needs no
 * special case in the database.
 */
public record AccountRef(OwnerKind ownerKind, UUID ownerId, Bucket bucket) {

    /** The id the singleton owners use. Not a magic number so much as the
     *  absence of one — nothing generates it, so nothing collides with it. */
    public static final UUID SINGLETON = new UUID(0L, 0L);

    public AccountRef {
        if (ownerKind == null || bucket == null) {
            throw new IllegalArgumentException("An account needs an owner kind and a bucket");
        }
        if (ownerId == null) {
            ownerId = SINGLETON;
        }
    }

    public static AccountRef user(UUID userId, Bucket bucket) {
        return new AccountRef(OwnerKind.USER, userId, bucket);
    }

    public static AccountRef merchant(UUID merchantId, Bucket bucket) {
        return new AccountRef(OwnerKind.MERCHANT, merchantId, bucket);
    }

    /** Commissions and service fees — and, on orders that predate Phase 4 M1,
     *  the courier's fee and tip, which were held here under their own ledger
     *  kinds until there were couriers to pay them to. */
    public static AccountRef platform() {
        return new AccountRef(OwnerKind.PLATFORM, SINGLETON, Bucket.AVAILABLE);
    }

    public static AccountRef external() {
        return new AccountRef(OwnerKind.EXTERNAL, SINGLETON, Bucket.EXTERNAL);
    }

    public static AccountRef of(OwnerKind ownerKind, UUID ownerId, Bucket bucket) {
        return new AccountRef(ownerKind, ownerId, bucket);
    }

    /** The same owner's other pocket — what a hold and a release move between. */
    public AccountRef in(Bucket other) {
        return new AccountRef(ownerKind, ownerId, other);
    }
}
