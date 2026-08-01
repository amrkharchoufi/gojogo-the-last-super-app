package com.gojogo.partner.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.payments.AccountRef;
import com.gojogo.payments.Bucket;
import com.gojogo.payments.InsufficientFundsException;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.TokenApi;
import com.gojogo.payments.WalletApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The $30, and what happens to it.
 *
 * <p>The tests worth having here are the ones about money that must <em>not</em>
 * move: a stake charged twice, a fee larger than what is left, a release on a
 * suspension. Each is invisible when it goes wrong — nothing errors, a balance is
 * simply the wrong number — which is exactly the class of defect a ledger exists
 * to make impossible and a test has to hold it to.
 */
class PartnerStakeTests {

    private static final UUID DRIVER = UUID.randomUUID();

    private WalletApi wallet;
    private TokenApi tokens;
    private ConfigApi config;
    private PartnerStakeService stakes;
    private PartnerAccount account;

    @BeforeEach
    void setUp() {
        wallet = mock(WalletApi.class);
        tokens = mock(TokenApi.class);
        config = mock(ConfigApi.class);
        // The compiled-in defaults are the contract: an empty config table has
        // to behave exactly like a populated one.
        when(config.number(anyString(), anyLong()))
            .thenAnswer(call -> call.getArgument(1, Long.class));
        when(wallet.currency()).thenReturn("USD");
        when(wallet.transfer(any(), any(), anyLong(), any(), any(), anyString()))
            .thenReturn(new WalletApi.Movement(UUID.randomUUID(), 0, false));
        stakes = new PartnerStakeService(wallet, tokens, config);
        account = new PartnerAccount(DRIVER, PartnerKind.DRIVER, "Amina drives");
    }

    @Test
    @DisplayName("a driver stakes $30; a restaurant stakes nothing")
    void whoStakes() {
        assertThat(stakes.requiredStakeMinor(PartnerKind.DRIVER)).isEqualTo(3000);
        assertThat(stakes.requiredStakeMinor(PartnerKind.COURIER)).isEqualTo(3000);
        // A restaurant's commitment is a licence and a kitchen; a stake would be
        // a tax on applying.
        assertThat(stakes.requiredStakeMinor(PartnerKind.RESTAURANT)).isZero();
        assertThat(stakes.isStakeRequired(PartnerKind.RESTAURANT)).isFalse();
    }

    @Test
    @DisplayName("the stake stays the applicant's money — their AVAILABLE into "
        + "their own STAKING, not the platform's pocket")
    void stakeIsHeldNotTaken() {
        stakes.payStake(account);

        ArgumentCaptor<AccountRef> from = ArgumentCaptor.forClass(AccountRef.class);
        ArgumentCaptor<AccountRef> to = ArgumentCaptor.forClass(AccountRef.class);
        verify(wallet).transfer(from.capture(), to.capture(), eq(3000L), eq(LedgerKind.STAKE),
            any(), anyString());
        assertThat(from.getValue()).isEqualTo(AccountRef.user(DRIVER, Bucket.AVAILABLE));
        assertThat(to.getValue()).isEqualTo(AccountRef.user(DRIVER, Bucket.STAKING));
        assertThat(account.hasLiveStake()).isTrue();
    }

    @Test
    @DisplayName("paying twice moves money once, and the key is derived from the "
        + "application rather than a clock")
    void stakeIsIdempotent() {
        stakes.payStake(account);
        stakes.payStake(account);

        verify(wallet, times(1)).transfer(any(), any(), anyLong(), any(), any(),
            eq("partner:" + account.getId() + ":stake"));
    }

    @Test
    @DisplayName("an empty wallet is a 402 the app can act on, and records nothing")
    void insufficientFundsRecordsNothing() {
        when(wallet.transfer(any(), any(), anyLong(), any(), any(), anyString()))
            .thenThrow(new InsufficientFundsException(3000, 1200, "USD"));

        assertThatThrownBy(() -> stakes.payStake(account))
            .isInstanceOf(InsufficientFundsException.class);
        // An application that believes it is staked while the ledger disagrees
        // is the one state that must not exist.
        assertThat(account.hasLiveStake()).isFalse();
        assertThat(account.getStakeAmountMinor()).isZero();
    }

    @Test
    @DisplayName("the ID check is paid out of the stake, not out of the wallet")
    void kycFeeComesOutOfTheStake() {
        stakes.payStake(account);

        stakes.chargeKycFee(account, true);

        ArgumentCaptor<AccountRef> from = ArgumentCaptor.forClass(AccountRef.class);
        verify(wallet).transfer(from.capture(), eq(AccountRef.platform()), eq(500L),
            eq(LedgerKind.FEE), any(), anyString());
        assertThat(from.getValue()).isEqualTo(AccountRef.user(DRIVER, Bucket.STAKING));
        assertThat(account.getKycFeeMinor()).isEqualTo(500);
        assertThat(account.remainingStakeMinor()).isEqualTo(2500);
    }

    @Test
    @DisplayName("a zero retry fee writes no ledger entry at all")
    void zeroFeeIsNotAMovement() {
        stakes.payStake(account);

        stakes.chargeKycFee(account, false);

        // An entry whose only content is that a policy is off is noise in a
        // statement somebody has to read.
        verify(wallet, never()).transfer(any(), any(), anyLong(), eq(LedgerKind.FEE),
            any(), anyString());
        assertThat(account.getKycFeeMinor()).isZero();
    }

    @Test
    @DisplayName("a fee bigger than what's left takes what's left, and never puts "
        + "the stake into debt")
    void feeIsCappedByTheRemainingStake() {
        when(config.number(eq("partner.kyc.fee.minor"), anyLong())).thenReturn(9999L);
        stakes.payStake(account);

        stakes.chargeKycFee(account, true);

        verify(wallet).transfer(any(), any(), eq(3000L), eq(LedgerKind.FEE), any(), anyString());
        assertThat(account.remainingStakeMinor()).isZero();
    }

    @Test
    @DisplayName("a release gives back the stake less the fees, and only once")
    void releaseReturnsWhatIsLeft() {
        stakes.payStake(account);
        stakes.chargeKycFee(account, true);

        stakes.releaseStake(account);
        stakes.releaseStake(account);

        verify(wallet, times(1)).transfer(eq(AccountRef.user(DRIVER, Bucket.STAKING)),
            eq(AccountRef.user(DRIVER, Bucket.AVAILABLE)), eq(2500L),
            eq(LedgerKind.STAKE_RELEASE), any(), anyString());
        assertThat(account.hasLiveStake()).isFalse();
        assertThat(account.getStakeReleasedAt()).isNotNull();
    }

    @Test
    @DisplayName("releasing a stake the fees ate moves nothing but still clears it")
    void releasingAnEmptyStakeMovesNothing() {
        when(config.number(eq("partner.kyc.fee.minor"), anyLong())).thenReturn(3000L);
        stakes.payStake(account);
        stakes.chargeKycFee(account, true);

        stakes.releaseStake(account);

        verify(wallet, never()).transfer(any(), any(), anyLong(), eq(LedgerKind.STAKE_RELEASE),
            any(), anyString());
        assertThat(account.hasLiveStake()).isFalse();
    }

    @Test
    @DisplayName("the stake page carries the shortfall, so an empty wallet becomes "
        + "a top-up button rather than a dead end")
    void statusNamesTheShortfall() {
        when(wallet.balancesOf(any(), eq(DRIVER)))
            .thenReturn(new WalletApi.Balances("USD", 1200, 0, 0, 0, 0));

        StakeStatus status = stakes.statusOf(account);

        assertThat(status.required()).isTrue();
        assertThat(status.requiredMinor()).isEqualTo(3000);
        assertThat(status.walletAvailableMinor()).isEqualTo(1200);
        assertThat(status.shortfallMinor()).isEqualTo(1800);
    }

    @Test
    @DisplayName("a wallet that already covers it has no shortfall — never a "
        + "negative one")
    void shortfallNeverGoesNegative() {
        when(wallet.balancesOf(any(), eq(DRIVER)))
            .thenReturn(new WalletApi.Balances("USD", 9000, 0, 0, 0, 0));

        assertThat(stakes.statusOf(account).shortfallMinor()).isZero();
    }
}
