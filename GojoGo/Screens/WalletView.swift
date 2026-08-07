import SwiftUI

// MARK: - GoJo Wallet (Phase 2e · Milestone 3)
//
// The first screen in this app that is about money rather than content. It shows
// one number people care about — what they can spend — and, underneath it, the
// honest version: what is held against an order in flight, and every movement
// that got them here.
//
// There is no card form, and there never will be one. Topping up hands off to a
// Stripe-hosted page in a system sheet, so card details never pass through
// anything in this codebase. The button that starts it is hidden entirely on an
// environment with no Stripe credentials rather than shown and then refused.
//
// Design follows the Economy sheets: tinted glass cards, mono for numbers, one
// ink capsule for the primary action.

struct WalletView: View {
    @EnvironmentObject var app: AppState

    /// Top-up amounts, in minor units. Fixed choices rather than a keypad: this
    /// is a wallet people fund to buy lunch, and four taps beats a number pad.
    private static let amounts = [1_000, 2_000, 5_000, 10_000]

    private var currency: String { app.wallet?.currency ?? "USD" }

    var body: some View {
        VStack(spacing: 0) {
            if let notice = app.walletNotice {
                EconomyNoticeBanner(message: notice) { app.walletNotice = nil }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            header
            ScrollView {
                VStack(spacing: 20) {
                    balanceCard
                    if app.walletTopUpAvailable { topUp }
                    activity
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .animation(.ggOverlay, value: app.walletNotice)
        .task { await app.refreshWallet() }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("GOJO WALLET")
                    .font(.ggMono(11, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(GGColor.textSecondary)
                Text("Your balance")
                    .font(.gg(22, .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            Spacer()
            Button {
                app.showWallet = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(GGColor.surface))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: Balance

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(WalletStore.money(app.wallet?.availableMinor ?? 0, currency: currency))
                .font(.ggMono(38, .bold))
                .foregroundStyle(GGColor.textPrimary)
                .contentTransition(.numericText())

            // Held money is still the customer's, so it is shown as part of
            // their balance rather than as something taken from them — the
            // distinction the ESCROW bucket exists to make.
            // One bucket, many possible reasons to be in it: a delivery, a shop
            // order, a booking, an ownership transfer, several at once. The old
            // wording named a single "order in flight", which was wrong on both
            // counts for the common case — a $125 hold that was actually two
            // service bookings reads as one order nobody can find.
            if let escrow = app.wallet?.escrowMinor, escrow > 0 {
                Label("\(WalletStore.money(escrow, currency: currency)) held until what you've booked and bought is settled",
                      systemImage: "clock.arrow.circlepath")
                    .font(.gg(13))
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Phase 3's buckets, shown only once they hold something — an empty
            // "Tokens 0" row on every wallet would be a promise, not a feature.
            //
            // Tokens are counted rather than priced: the ledger holds them as
            // money (a token is a fixed number of minor units) but the thing a
            // driver has is a number of trips, and "$12.00" here would be asking
            // them to divide. Buying them lives in Driver Mode, which is the
            // only place they mean anything.
            let extras: [(String, String)] = [
                ("Staked", moneyOrNil(app.wallet?.stakingMinor)),
                ("Tokens", app.wallet.map { $0.tokenCount > 0 ? "\($0.tokenCount)" : "" } ?? ""),
                ("Rewards", moneyOrNil(app.wallet?.rewardsMinor))
            ].filter { !$0.1.isEmpty }
            if !extras.isEmpty {
                HStack(spacing: 16) {
                    ForEach(extras, id: \.0) { name, value in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name.uppercased())
                                .font(.ggMono(10, .semibold))
                                .foregroundStyle(GGColor.textTertiary)
                            Text(value)
                                .font(.ggMono(14, .semibold))
                                .foregroundStyle(GGColor.textPrimary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(GGColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(GGColor.hairline, lineWidth: 1))
    }

    /// Money, or nothing at all for an empty bucket.
    private func moneyOrNil(_ minor: Int?) -> String {
        guard let minor, minor > 0 else { return "" }
        return WalletStore.money(minor, currency: currency)
    }

    // MARK: Top up

    private var topUp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add money")
                .font(.gg(15, .semibold))
                .foregroundStyle(GGColor.textPrimary)
            HStack(spacing: 10) {
                ForEach(Self.amounts, id: \.self) { amount in
                    Button {
                        app.topUpWallet(amountMinor: amount)
                    } label: {
                        Text(WalletStore.money(amount, currency: currency))
                            .font(.ggMono(14, .semibold))
                            .foregroundStyle(GGColor.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(GGColor.white))
                    }
                    .disabled(app.walletBusy)
                    .opacity(app.walletBusy ? 0.5 : 1)
                }
            }
            Text("Payment is handled by Stripe — your card details never reach GoJoGo.")
                .explanatory(12)
                .foregroundStyle(GGColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(GGColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(GGColor.hairline, lineWidth: 1))
    }

    // MARK: Activity

    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity")
                .font(.gg(15, .semibold))
                .foregroundStyle(GGColor.textPrimary)

            if app.walletTransactions.isEmpty {
                Text("Nothing yet. Top up, and anything you spend or receive shows up here.")
                    .explanatory(13)
                    .foregroundStyle(GGColor.textSecondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(app.walletTransactions.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().overlay(GGColor.hairline)
                        }
                        WalletRow(entry: entry)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(GGColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(GGColor.hairline, lineWidth: 1))
    }
}

/// One movement. The sign is the server's, not the app's — the statement is
/// already written from this person's point of view.
private struct WalletRow: View {
    let entry: WalletTransactionDTO

    private var incoming: Bool { entry.amountMinor >= 0 }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: incoming ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(incoming ? GGColor.textPrimary : GGColor.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(GGColor.surface2))

            VStack(alignment: .leading, spacing: 2) {
                Text(WalletStore.describe(entry))
                    .font(.gg(14, .medium))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(1)
                Text(BackendDate.relative(entry.createdAt))
                    .font(.gg(11))
                    .foregroundStyle(GGColor.textTertiary)
            }
            Spacer(minLength: 8)

            Text((incoming ? "+" : "") + WalletStore.money(entry.amountMinor, currency: entry.currency))
                .font(.ggMono(14, .semibold))
                .foregroundStyle(GGColor.textPrimary)
        }
        .padding(.vertical, 12)
    }
}
