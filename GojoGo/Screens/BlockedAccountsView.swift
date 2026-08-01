import SwiftUI

// MARK: - Blocked accounts (Phase 2e · Milestone 5)
//
// The list is one-directional on purpose: it holds the accounts *you* blocked,
// which are the only ones you can do anything about. There is no way to ask who
// blocked you, here or on the wire — being told would just be a prompt to open a
// second account.
//
// Unblocking restores visibility and nothing else. The follows a block removed
// stay removed, and the screen says so, because the alternative is somebody
// quietly getting their audience back without being asked.

struct BlockedAccountsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            if app.blockedAccounts.isEmpty {
                empty
            } else {
                list
            }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .task { await app.refreshBlockedAccounts() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BLOCKED")
                    .font(.ggMono(11, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(GGColor.textSecondary)
                Text(app.blockedAccounts.isEmpty
                     ? "Nobody"
                     : "\(app.blockedAccounts.count) account\(app.blockedAccounts.count == 1 ? "" : "s")")
                    .font(.gg(22, .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            Spacer()
            Button { app.showBlockedAccounts = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(GGColor.surface))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "hand.raised")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(GGColor.textTertiary)
            Text("You haven't blocked anyone")
                .font(.gg(16))
                .foregroundStyle(GGColor.textPrimary)
            Text("Blocking hides you from each other everywhere in the app.")
                .font(.gg(13))
                .multilineTextAlignment(.center)
                .foregroundStyle(GGColor.textSecondary)
                .padding(.horizontal, 44)
            Spacer()
        }
    }

    private var list: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(app.blockedAccounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 { Divider().overlay(GGColor.hairline) }
                    row(account)
                }
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(GGColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(GGColor.hairline, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.top, 6)

            Text("Unblocking lets you see each other again. It does not follow them again.")
                .font(.gg(12))
                .foregroundStyle(GGColor.textTertiary)
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 40)
        }
    }

    private func row(_ account: BlockedAccount) -> some View {
        HStack(spacing: 12) {
            UserAvatar(size: 38,
                       gradient: SampleData.g1,
                       letter: String((account.handle.isEmpty ? account.name : account.handle)
                        .prefix(1)).uppercased(),
                       imageURL: account.avatarURL)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.name)
                    .font(.gg(15))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(1)
                if !account.handle.isEmpty {
                    Text("@\(account.handle)")
                        .font(.ggMono(12))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await app.unblock(profileId: account.id) }
            } label: {
                Text("Unblock")
                    .font(.gg(13, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(GGColor.ink(0.08)))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.vertical, 11)
    }
}
