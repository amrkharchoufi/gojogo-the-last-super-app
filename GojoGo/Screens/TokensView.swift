import SwiftUI

// MARK: - Ride tokens (Phase 3 · Milestone 4)
//
// The driver's side of the money. GojoGo takes no commission on a fare — the
// driver keeps all of it — and sells the right to accept a job instead. This
// screen is where that happens, and where the one thing the rest of the app
// cannot say gets said.
//
// Dispatch never offers a trip to a driver who can't pay for it. That is the
// correct behaviour and it is completely silent: no error, no card, nothing.
// So the banner at the top of this screen is not decoration — it is the only
// place in the product that explains an empty Driver Mode.
//
// There is no card form. A pack is bought out of the wallet, and a wallet that
// is short offers a top-up for exactly the shortfall through the same
// Stripe-hosted page everything else uses.

struct TokensView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    private var currency: String { app.tokenWallet?.currency ?? "USD" }

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
                    if let refusal = app.tokenRefusal { warning(refusal) }
                    balanceCard
                    packs
                    priceList
                    movements
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .animation(.ggOverlay, value: app.walletNotice)
        .animation(.ggOverlay, value: app.rideTokens)
        .task { await app.refreshTokens() }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("RIDE TOKENS")
                    .font(.ggMono(11, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(GGColor.textSecondary)
                Text("What it costs to take a trip")
                    .font(.gg(22, .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            Spacer()
            Button {
                dismiss()
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

    /// The sentence the server wrote. Never composed here — only the module
    /// that prices a ride knows whether a balance is enough to take one.
    private func warning(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Text(message)
                .font(.gg(13, .medium))
                .foregroundStyle(GGColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(GGColor.ink(0.12)))
    }

    // MARK: Balance

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(app.tokenBalance)")
                    .font(.ggMono(38, .bold))
                    .foregroundStyle(GGColor.textPrimary)
                    .contentTransition(.numericText())
                Text(app.tokenBalance == 1 ? "token" : "tokens")
                    .font(.gg(15, .semibold))
                    .foregroundStyle(GGColor.textSecondary)
            }

            if let cheapest = app.rideTokens?.cheapest, cheapest > 0 {
                Text("The cheapest trip costs \(cheapest) — that's about "
                     + "\(app.tokenBalance / max(1, cheapest)) more \(app.tokenBalance / max(1, cheapest) == 1 ? "trip" : "trips") at this balance.")
                    .explanatory(13)
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(GGColor.hairline)

            HStack {
                Text("Wallet")
                    .font(.ggMono(10, .semibold))
                    .foregroundStyle(GGColor.textTertiary)
                Spacer()
                Text(WalletStore.money(app.tokenWallet?.availableMinor ?? 0,
                                       currency: currency))
                    .font(.ggMono(14, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }

            // The shortfall the last purchase was refused for, turned into one
            // tap. Two steps ("go and top up, then come back") is where people
            // give up.
            if let shortfall = app.pendingTokenTopUpMinor, shortfall > 0 {
                Button {
                    app.topUpForTokens()
                } label: {
                    Text("Add \(WalletStore.money(shortfall, currency: currency)) to your wallet")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())
                .disabled(app.walletBusy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(GGColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(GGColor.hairline, lineWidth: 1))
    }

    // MARK: Packs

    @ViewBuilder
    private var packs: some View {
        let shelf = app.tokenWallet?.packs ?? []
        if !shelf.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top up tokens")
                    .font(.gg(15, .semibold))
                    .foregroundStyle(GGColor.textPrimary)

                VStack(spacing: 0) {
                    ForEach(Array(shelf.enumerated()), id: \.element.id) { index, pack in
                        if index > 0 { Divider().overlay(GGColor.hairline) }
                        packRow(pack)
                    }
                }

                Text("Paid from your GoJo Wallet. The fare is yours in full — a token is what GoJoGo charges for the job.")
                    .explanatory(12)
                    .foregroundStyle(GGColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(GGColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(GGColor.hairline, lineWidth: 1))
        }
    }

    private func packRow(_ pack: TokenPackDTO) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(pack.tokens) tokens")
                    .font(.gg(15, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                // The bonus is stated because it is real: the platform funds it
                // as its own ledger entry rather than the pack quietly being
                // "good value".
                if pack.bonusTokens > 0 {
                    Text("\(pack.bonusTokens) on us")
                        .font(.gg(12))
                        .foregroundStyle(GGColor.textSecondary)
                } else if !pack.note.isEmpty {
                    Text(pack.note)
                        .font(.gg(12))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button {
                app.buyTokenPack(pack)
            } label: {
                Text(WalletStore.money(pack.priceMinor, currency: currency))
                    .font(.ggMono(14, .semibold))
                    .foregroundStyle(GGColor.onAccent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
            .disabled(app.tokensBusy)
            .opacity(app.tokensBusy ? 0.5 : 1)
        }
        .padding(.vertical, 12)
    }

    // MARK: What a trip costs

    @ViewBuilder
    private var priceList: some View {
        let prices = app.rideTokens?.prices ?? []
        if !prices.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("What a trip costs")
                    .font(.gg(15, .semibold))
                    .foregroundStyle(GGColor.textPrimary)

                ForEach(categoriesInOrder(prices), id: \.self) { category in
                    HStack(spacing: 10) {
                        Text(category.capitalized)
                            .font(.gg(13, .medium))
                            .foregroundStyle(GGColor.textPrimary)
                            .frame(width: 78, alignment: .leading)
                        Text(bandsLabel(for: category, in: prices))
                            .font(.ggMono(12))
                            .foregroundStyle(GGColor.textSecondary)
                        Spacer(minLength: 0)
                    }
                }

                Text("Charged when a trip is confirmed, and returned in full if it's cancelled.")
                    .explanatory(12)
                    .foregroundStyle(GGColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(GGColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(GGColor.hairline, lineWidth: 1))
        }
    }

    /// Categories in the order the server sent them, without repeats — the app
    /// does not have an opinion about which vehicle should be listed first.
    private func categoriesInOrder(_ prices: [RideTokenPriceDTO]) -> [String] {
        var seen: [String] = []
        for price in prices where !seen.contains(price.category) {
            seen.append(price.category)
        }
        return seen
    }

    /// "1 up to 3 km · 2 up to 10 km · 4 beyond". The last band of every
    /// category is the catch-all, so it is rendered as one rather than as a
    /// distance nobody will ever drive.
    private func bandsLabel(for category: String, in prices: [RideTokenPriceDTO]) -> String {
        let bands = prices.filter { $0.category == category }
            .sorted { $0.upToMetres < $1.upToMetres }
        return bands.enumerated().map { index, band in
            index == bands.count - 1
                ? "\(band.tokens) beyond"
                : "\(band.tokens) to \(band.upToMetres / 1000) km"
        }.joined(separator: " · ")
    }

    // MARK: History

    @ViewBuilder
    private var movements: some View {
        let history = app.tokenWallet?.movements ?? []
        VStack(alignment: .leading, spacing: 12) {
            Text("Token history")
                .font(.gg(15, .semibold))
                .foregroundStyle(GGColor.textPrimary)

            if history.isEmpty {
                Text("Nothing yet. Every top-up and every trip you take shows up here.")
                    .explanatory(13)
                    .foregroundStyle(GGColor.textSecondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().overlay(GGColor.hairline) }
                        TokenMovementRow(entry: entry,
                                         minorPerToken: app.tokenWallet?.minorPerToken ?? 100)
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

/// One token movement, counted in tokens.
///
/// The ledger holds money — a token is a fixed number of minor units — but a
/// driver counts trips, and a statement line reading "−$2.00" next to a trip
/// they took is asking them to do the division themselves.
private struct TokenMovementRow: View {
    let entry: WalletTransactionDTO
    let minorPerToken: Int

    private var incoming: Bool { entry.amountMinor >= 0 }
    private var tokens: Int { abs(entry.amountMinor) / max(1, minorPerToken) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: incoming ? "plus" : "minus")
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

            Text("\(incoming ? "+" : "−")\(tokens)")
                .font(.ggMono(14, .semibold))
                .foregroundStyle(GGColor.textPrimary)
        }
        .padding(.vertical, 12)
    }
}
