package com.gojogo.payments;

import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * How accounts are named. Small, but the ledger's uniqueness index is built on
 * these being equal when they should be — two spellings of "the platform's
 * available balance" would silently become two platform balances.
 */
class AccountRefTests {

    @Test
    void singletonsCollapseToOneIdentity() {
        assertThat(AccountRef.platform())
            .isEqualTo(new AccountRef(OwnerKind.PLATFORM, null, Bucket.AVAILABLE))
            .isEqualTo(new AccountRef(OwnerKind.PLATFORM, AccountRef.SINGLETON, Bucket.AVAILABLE));
        assertThat(AccountRef.external().ownerId()).isEqualTo(AccountRef.SINGLETON);
    }

    @Test
    void inKeepsTheOwnerAndChangesThePocket() {
        UUID user = UUID.randomUUID();
        AccountRef available = AccountRef.user(user, Bucket.AVAILABLE);
        AccountRef escrow = available.in(Bucket.ESCROW);
        assertThat(escrow.ownerId()).isEqualTo(user);
        assertThat(escrow.ownerKind()).isEqualTo(OwnerKind.USER);
        assertThat(escrow.bucket()).isEqualTo(Bucket.ESCROW);
        assertThat(escrow).isNotEqualTo(available);
    }

    @Test
    void anAccountAlwaysHasAnOwnerKindAndABucket() {
        assertThatThrownBy(() -> new AccountRef(null, UUID.randomUUID(), Bucket.AVAILABLE))
            .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new AccountRef(OwnerKind.USER, UUID.randomUUID(), null))
            .isInstanceOf(IllegalArgumentException.class);
    }

    /** Shortfall never goes negative — a wallet with more than enough is not
     *  "short by minus five", it is fine. */
    @Test
    void shortfallIsWhatIsMissing() {
        assertThat(new InsufficientFundsException(2_000, 750, "USD").shortfallMinor())
            .isEqualTo(1_250);
        assertThat(new InsufficientFundsException(500, 900, "USD").shortfallMinor()).isZero();
    }
}
